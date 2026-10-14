// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

#include "lxqtukz-settings/src/application.h"

#include <QtCore/QTemporaryFile>
#include <QtCore/QTextStream>
#include <QtGui/QPalette>

// The KDE desktop style colors its controls from a KDE color scheme, not from
// the palette. Outside Plasma there is none, so it falls back to Breeze's light
// colors, and a dark theme gets dark text on a dark window. This writes one
// from the palette every other Qt app uses, and points the style at it.
static void schemeFromPalette(QApplication &app)
{
	// Kept for the life of the app, and removed on exit.
	static QTemporaryFile file;
	if (!file.open())
		return;

	const QPalette pal = app.palette();
	const auto rgb = [&pal](QPalette::ColorRole role) {
		const QColor c = pal.color(QPalette::Active, role);
		return QStringLiteral("%1,%2,%3").arg(c.red()).arg(c.green()).arg(c.blue());
	};
	struct Set {
		const char *name;
		QPalette::ColorRole back, alternate, text;
	};
	const Set sets[] = {
		{"Window", QPalette::Window, QPalette::Window, QPalette::WindowText},
		{"Header", QPalette::Window, QPalette::Window, QPalette::WindowText},
		{"View", QPalette::Base, QPalette::AlternateBase, QPalette::Text},
		{"Button", QPalette::Button, QPalette::Button, QPalette::ButtonText},
		{"Selection", QPalette::Highlight, QPalette::Highlight, QPalette::HighlightedText},
		{"Tooltip", QPalette::ToolTipBase, QPalette::ToolTipBase, QPalette::ToolTipText},
	};

	// Keys left out, such as the negative and positive text colors, keep
	// KDE's own defaults.
	QTextStream out(&file);
	for (const Set &set : sets) {
		out << "[Colors:" << set.name << "]\n"
			<< "BackgroundNormal=" << rgb(set.back) << "\n"
			<< "BackgroundAlternate=" << rgb(set.alternate) << "\n"
			<< "ForegroundNormal=" << rgb(set.text) << "\n"
			<< "ForegroundInactive=" << rgb(QPalette::PlaceholderText) << "\n"
			<< "ForegroundActive=" << rgb(QPalette::Highlight) << "\n"
			<< "ForegroundLink=" << rgb(QPalette::Link) << "\n"
			<< "ForegroundVisited=" << rgb(QPalette::LinkVisited) << "\n"
			<< "DecorationFocus=" << rgb(QPalette::Highlight) << "\n"
			<< "DecorationHover=" << rgb(QPalette::Highlight) << "\n\n";
	}
	out.flush();
	file.flush();
	app.setProperty("KDE_COLOR_SCHEME_PATH", file.fileName());
}

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
	schemeFromPalette(*app);
	return app;
}

int execApplication(QApplication &app)
{
	return app.exec();
}
