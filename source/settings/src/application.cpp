// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

#include "lxqtukz-settings/src/application.h"

std::unique_ptr<QApplication> newApplication()
{
	// Qt keeps these for the life of the application.
	static int argc = 1;
	static char name[] = "lxqtukz-settings";
	static char *argv[] = {name, nullptr};
	auto app = std::make_unique<QApplication>(argc, argv);
	QApplication::setApplicationName(QStringLiteral("lxqtukz-settings"));
	QApplication::setApplicationDisplayName(QStringLiteral("Settings"));
	QApplication::setDesktopFileName(QStringLiteral("lxqtukz-settings"));
	return app;
}

int execApplication(QApplication &app)
{
	return app.exec();
}
