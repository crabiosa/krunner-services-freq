# SPDX-FileCopyrightText: 2026 krunner-services-freq contributors
# SPDX-License-Identifier: LGPL-2.0-only
#
# Runs on the sources of plasma-workspace/runners/services (LGPL-2.0-only),
# turned into a separately installable runner with a frequency ranking.

cmake_minimum_required(VERSION 3.16)

project(krunner_services_freq VERSION 0.1.0)

set(QT_MIN_VERSION 6.5.0)
set(KF_MIN_VERSION 6.19.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n JobWidgets KIO Runner Service)
find_package(PlasmaActivities REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"krunner_services_freq\")

kcoreaddons_add_plugin(krunner_services_freq
    SOURCES src/servicerunner.cpp src/launchstats.cpp
    INSTALL_NAMESPACE "kf6/krunner"
)

ecm_qt_declare_logging_category(krunner_services_freq
    HEADER debug.h
    IDENTIFIER RUNNER_SERVICES
    CATEGORY_NAME org.kde.krunner.servicesfreq
    DEFAULT_SEVERITY Warning
    DESCRIPTION "krunner services freq"
)

target_link_libraries(krunner_services_freq
    KF6::CoreAddons
    KF6::I18n
    KF6::JobWidgets
    KF6::KIOGui
    KF6::Runner
    KF6::Service
    Plasma::Activities
)
