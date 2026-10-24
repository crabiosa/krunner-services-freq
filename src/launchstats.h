/*
    SPDX-FileCopyrightText: 2026 krunner-services-freq contributors
    SPDX-License-Identifier: LGPL-2.0-only
*/

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QHash>
#include <QString>

/**
 * Launch counters for applications and their desktop actions.
 *
 * The file is a snapshot, not a log: one line per record,
 *
 *   # count|last_used|desktop-id|action
 *   34|1792521554|org.kde.konsole.desktop|
 *
 * Identifiers are percent-encoded, so '|' can never appear inside a field.
 * The file lives in XDG_STATE_HOME, and the runner treats it as a cache:
 * deleting it just loses the history.
 */
class LaunchStats
{
public:
    struct Record {
        quint32 count = 0;
        qint64 lastUsed = 0; // seconds since epoch
    };

    /** $XDG_STATE_HOME/krunner-services-freq/counts */
    static QString filePath();

    /** Key for (desktop id, action); an empty action means the application itself. */
    static QString key(const QString &desktopId, const QString &action = QString());

    /**
     * Record for the key, or an empty one. Reloads the file when it changed
     * underneath us, which is normal: krunner and plasmashell share it.
     */
    Record lookup(const QString &key);

    /**
     * Adds one launch. The action also counts as a launch of the application,
     * the application does not count as a launch of its actions.
     */
    void increment(const QString &desktopId, const QString &action = QString());

    /** Ranking multiplier: 1.0 for unknown records, up to 1.5 for a daily favourite. */
    static double multiplier(const Record &record, qint64 now = QDateTime::currentSecsSinceEpoch());

private:
    void incrementOne(const QString &desktopId, const QString &action);
    void reloadIfChanged();
    void writeThrough();

    QHash<QString, Record> m_records;
    QDateTime m_mtime;
    qint64 m_size = -1;
};
