/*
    SPDX-FileCopyrightText: 2026 krunner-services-freq contributors
    SPDX-License-Identifier: LGPL-2.0-only
*/

#include "launchstats.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>
#include <cmath>

#include "debug.h"

namespace
{
constexpr quint32 maxCount = 30; // saturation happens long before this
constexpr double halfLifeDays = 14.0;
constexpr double saturationRate = 0.3;
constexpr double maxBonus = 0.5;

QString stateDir()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation);
    return (base.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/state") : base) + QStringLiteral("/krunner-services-freq");
}

QString encode(const QString &value)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(value));
}
} // namespace

QString LaunchStats::filePath()
{
    return stateDir() + QStringLiteral("/counts");
}

QString LaunchStats::key(const QString &desktopId, const QString &action)
{
    return encode(desktopId) + QLatin1Char('|') + encode(action);
}

LaunchStats::Record LaunchStats::lookup(const QString &key)
{
    reloadIfChanged();
    return m_records.value(key);
}

double LaunchStats::multiplier(const Record &record, qint64 now)
{
    if (record.count == 0) {
        return 1.0;
    }
    const quint32 count = std::min(record.count, maxCount);
    const double saturation = 1.0 - std::exp(-saturationRate * static_cast<double>(count));
    const double ageDays = record.lastUsed > 0 ? std::max(0.0, static_cast<double>(now - record.lastUsed) / 86400.0) : 0.0;
    const double decay = std::pow(0.5, ageDays / halfLifeDays);
    // The decay applies to the bonus, not to the counter: a saturated record
    // that has not been used for a month must not stay at its maximum.
    return 1.0 + maxBonus * saturation * decay;
}

void LaunchStats::increment(const QString &desktopId, const QString &action)
{
    if (desktopId.isEmpty()) {
        return;
    }

    // Read-modify-write, and a nested action launch bumps both records, so the
    // same process may write twice in a row. Both steps reload from disk.
    reloadIfChanged();
    incrementOne(desktopId, action);
    if (!action.isEmpty()) {
        incrementOne(desktopId, QString());
    }
    writeThrough();
}

void LaunchStats::incrementOne(const QString &desktopId, const QString &action)
{
    Record &record = m_records[key(desktopId, action)];
    record.count = std::min(record.count + 1, maxCount);
    record.lastUsed = QDateTime::currentSecsSinceEpoch();
}

void LaunchStats::reloadIfChanged()
{
    const QFileInfo info(filePath());
    if (!info.exists()) {
        m_records.clear();
        m_mtime = QDateTime();
        m_size = -1;
        return;
    }
    if (info.size() == m_size && info.lastModified() == m_mtime) {
        return;
    }

    QFile file(filePath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qCWarning(RUNNER_SERVICES) << "cannot read" << filePath() << file.errorString();
        return;
    }

    QHash<QString, Record> records;
    int badLines = 0;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        const QStringList fields = line.split(QLatin1Char('|'));
        bool countOk = false;
        bool timeOk = false;
        if (fields.size() == 4) {
            const quint32 count = fields.at(0).toUInt(&countOk);
            const qint64 lastUsed = fields.at(1).toLongLong(&timeOk);
            if (countOk && timeOk && count > 0) {
                records.insert(fields.at(2) + QLatin1Char('|') + fields.at(3), Record{count, lastUsed});
                continue;
            }
        }
        ++badLines;
    }
    if (badLines > 0) {
        qCWarning(RUNNER_SERVICES) << "skipped" << badLines << "bad line(s) in" << filePath();
    }

    m_records = records;
    m_mtime = info.lastModified();
    m_size = info.size();
}

void LaunchStats::writeThrough()
{
    const QString dir = stateDir();
    if (!QDir().mkpath(dir)) {
        qCWarning(RUNNER_SERVICES) << "cannot create" << dir;
        return;
    }
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

    QByteArray data;
    data.append("# count|last_used|desktop-id|action\n");
    QStringList keys = m_records.keys();
    std::sort(keys.begin(), keys.end());
    for (const QString &key : keys) {
        const Record &record = m_records[key];
        data.append(QString::number(record.count).toUtf8());
        data.append('|');
        data.append(QString::number(record.lastUsed).toUtf8());
        data.append('|');
        data.append(key.toUtf8());
        data.append('\n');
    }

    QSaveFile file(filePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qCWarning(RUNNER_SERVICES) << "cannot write" << filePath() << file.errorString();
        return;
    }
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    if (file.write(data) != data.size() || !file.commit()) {
        qCWarning(RUNNER_SERVICES) << "cannot write" << filePath() << file.errorString();
        return;
    }

    // Our own write is the newest state; do not reload it on the next lookup.
    const QFileInfo info(filePath());
    m_mtime = info.lastModified();
    m_size = info.size();
}
