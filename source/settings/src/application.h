// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

// A QApplication rather than a QGuiApplication: the KDE desktop style for Qt
// Quick draws through the Qt widget style, which only a QApplication has.

#pragma once

#include <QtWidgets/QApplication>
#include <memory>

std::unique_ptr<QApplication> newApplication();
int execApplication(QApplication &app);
