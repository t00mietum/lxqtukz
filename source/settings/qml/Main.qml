// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

// Lays out whatever settings_ui.shcl declares. Nothing here knows a setting by
// name: rows come from the declarations, and values from the backend.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import org.lxqtukz.settings

ApplicationWindow {
	id: win
	title: qsTr("Settings")
	// Shown once sized. See fitContent.
	visible: false
	minimumWidth: 320
	minimumHeight: 240

	Backend {
		id: backend
	}

	readonly property var decl: JSON.parse(backend.declarations())
	readonly property var lay: decl.layout
	property int current: 0
	property int popupsOpen: 0
	property bool closing: false
	property bool liveErrorShown: false
	// Enter in the key repeat test area is a key to hold, not OK.
	property bool tryingKeys: false

	FontMetrics {
		id: fm
	}
	FontMetrics {
		id: fmBold
		font.bold: true
	}

	readonly property real rowHeight: Math.ceil(Math.max(lay.row_height, fm.height + lay.row_pad))
	readonly property real headerHeight: Math.ceil(fm.height + lay.header_pad)
	readonly property real tabHeight: Math.ceil(fm.height + lay.tab_pad_v)

	// Tabs with no tabs under them, in list order. The tab chords walk these.
	readonly property var leaves: {
		const out = []
		for (let i = 0; i < decl.tabs.length; i++)
			if (!decl.tabs[i].parent)
				out.push(i)
		return out
	}

	function isUnder(tab, ancestor) {
		return tab === ancestor || decl.tabs[tab].path.startsWith(decl.tabs[ancestor].path + "/")
	}

	function openTab(i) {
		if (!decl.tabs[i].parent) {
			current = i
		} else if (!isUnder(current, i)) {
			for (const leaf of leaves)
				if (isUnder(leaf, i)) {
					current = leaf
					break
				}
		}
	}

	function stepTab(by) {
		const at = leaves.indexOf(current)
		current = leaves[(at + by + leaves.length) % leaves.length]
	}

	// The rows of one tab, each told what it needs for spacing: whether it is
	// first, whether it leads a sub-group, and whether it is a heading that
	// only repeats its tab's title, which takes no space.
	function rowsOf(tab) {
		const rows = decl.rows.filter(r => r.tab === tab)
		return rows.map((r, i) => {
			const next = rows[i + 1]
			return Object.assign({}, r, {
				first: i === 0,
				leads: r.kind !== "heading" && next !== undefined && next.indent > r.indent,
				silent: r.kind === "heading" && r.label === decl.tabs[tab].title
			})
		})
	}

	function heightOf(r) {
		if (r.kind === "heading")
			return r.silent ? 0 : headerHeight + (r.first ? 0 : lay.header_gap)
		return rowHeight + (r.leads ? lay.subgroup_gap : 0)
	}

	readonly property real labelColumn: {
		let w = lay.label_width
		for (const r of decl.rows)
			if (r.kind !== "heading") {
				const mark = r.warning ? fm.advanceWidth(" " + decl.icons.warning) : 0
				w = Math.max(w, fm.advanceWidth(r.label) + mark + r.indent * lay.indent + lay.label_gap)
			}
		return Math.ceil(w)
	}

	readonly property real controlColumn: {
		let w = Math.max(lay.control_width, lay.text_width)
		for (const r of decl.rows)
			if (r.kind === "dropdown")
				for (const o of r.options)
					w = Math.max(w, fm.advanceWidth(o) + 3 * rowHeight)
		return Math.ceil(w)
	}

	readonly property real tabColumn: {
		let w = lay.tab_width
		for (const t of decl.tabs)
			w = Math.max(w, fmBold.advanceWidth(t.title) + t.depth * lay.tab_indent + 2 * lay.tab_pad)
		return Math.ceil(w)
	}

	readonly property real panelWidth: labelColumn + controlColumn + lay.test_width + lay.revert_width

	// The tallest tab sets the window's natural height.
	readonly property real panelHeight: {
		let h = 0
		for (const leaf of leaves)
			h = Math.max(h, rowsOf(leaf).reduce((sum, r) => sum + heightOf(r), 0))
		return Math.ceil(h)
	}

	function commitEdits() {
		// A field being typed in commits when it loses focus.
		focusSink.forceActiveFocus()
	}

	function apply() {
		const was = activeFocusItem
		commitEdits()
		if (!backend.apply())
			errorBox.show(false)
		if (was)
			was.forceActiveFocus()
	}

	function ok() {
		commitEdits()
		if (backend.apply()) {
			closing = true
			close()
		} else {
			errorBox.show(true)
		}
	}

	function cancel() {
		backend.cancel()
		closing = true
		close()
	}

	onClosing: close => {
		if (!closing)
			backend.cancel()
	}

	Component.onCompleted: {
		const start = backend.startTab()
		const found = decl.tabs.findIndex(t => t.path.toLowerCase() === start.toLowerCase())
		openTab(found >= 0 ? found : leaves[0])
		fitContent()
		visible = true
		// The style may settle its sizes a moment later.
		Qt.callLater(fitContent)
	}

	// With the app drawing its own title bar, the compositor's first size for
	// the window can count that bar in, which cuts the tallest tab off. It
	// comes before the window is first active, so one more fit then puts it
	// right, before anyone could have resized it.
	property bool refitted: false
	onActiveChanged: {
		if (active && !refitted) {
			refitted = true
			fitContent()
		}
	}

	// The natural size: the tallest tab and the widest row, plus the style's
	// own padding, capped to the screen's work area where the rows scroll.
	// The scroll bars' room is left out, since they go once it fits.
	function fitContent() {
		const w = tabColumn + scroller.contentWidth + scroller.leftPadding + scroller.rightPadding - scroller.effectiveScrollBarWidth + 1
		const h = scroller.topPadding + panelHeight + 2 * lay.pad + scroller.bottomPadding - scroller.effectiveScrollBarHeight + lay.buttons_gap + footer.implicitHeight + lay.pad + 1
		width = Math.min(Math.ceil(w), Screen.desktopAvailableWidth)
		height = Math.min(Math.ceil(h), Screen.desktopAvailableHeight)
	}

	Connections {
		target: backend
		// A save nobody asked for, such as a live edit, says so once a session.
		function onErrorChanged() {
			if (backend.error !== "" && !win.liveErrorShown && !errorBox.visible) {
				win.liveErrorShown = true
				errorBox.show(false)
			}
		}
		function onTestFailed(why) {
			errorBox.tell(qsTr("Test did not run"), why)
		}
	}

	Shortcut {
		sequences: ["Return", "Enter"]
		enabled: win.popupsOpen === 0 && !errorBox.visible && !win.tryingKeys
		onActivated: win.ok()
	}
	Shortcut {
		sequence: "Escape"
		enabled: win.popupsOpen === 0 && !errorBox.visible
		onActivated: win.cancel()
	}
	Shortcut {
		sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
		enabled: win.popupsOpen === 0
		onActivated: win.stepTab(1)
	}
	// Qt matches Ctrl+Shift+Tab against Ctrl+Backtab too, so listing both
	// makes the chord ambiguous and it never fires.
	Shortcut {
		sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]
		enabled: win.popupsOpen === 0
		onActivated: win.stepTab(-1)
	}

	Item {
		id: focusSink
		activeFocusOnTab: false
	}

	Dialog {
		id: errorBox
		property bool closeAfter: false
		property string message: ""
		function show(then) {
			closeAfter = then
			tell(qsTr("Not saved"), backend.error)
		}
		function tell(heading, text) {
			title = heading
			message = text
			open()
		}
		modal: true
		anchors.centerIn: parent
		width: Math.min(parent.width - 2 * lay.pad, 480)
		standardButtons: Dialog.Ok
		Label {
			width: parent.width
			wrapMode: Text.Wrap
			text: errorBox.message
		}
		onClosed: {
			if (closeAfter) {
				closeAfter = false
				win.closing = true
				win.close()
			}
		}
	}

	RowLayout {
		anchors.fill: parent
		spacing: 0

		// The tab list sits in a recessed gutter. Tabs are never focus stops.
		Rectangle {
			id: gutter
			Layout.preferredWidth: win.tabColumn
			Layout.fillHeight: true
			color: Qt.darker(win.palette.window, 1.08)

			Rectangle {
				anchors.right: parent.right
				width: 1
				height: parent.height
				color: win.palette.mid
			}

			ListView {
				id: tabList
				anchors.fill: parent
				anchors.topMargin: lay.pad
				anchors.rightMargin: 1
				model: decl.tabs
				boundsBehavior: Flickable.StopAtBounds
				currentIndex: win.current
				highlightFollowsCurrentItem: false
				onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

				delegate: Rectangle {
					required property var modelData
					required property int index
					readonly property bool lit: win.isUnder(win.current, index)
					width: ListView.view.width
					height: win.tabHeight
					color: lit ? Qt.lighter(gutter.color, 1.18) : "transparent"

					Label {
						x: lay.tab_pad + modelData.depth * lay.tab_indent
						anchors.verticalCenter: parent.verticalCenter
						text: modelData.title
						font.bold: lit && !modelData.parent
					}

					MouseArea {
						anchors.fill: parent
						onClicked: win.openTab(index)
					}
				}
			}
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.fillHeight: true
			spacing: 0

			ScrollView {
				id: scroller
				Layout.fillWidth: true
				Layout.fillHeight: true
				contentWidth: win.panelWidth + 2 * lay.pad
				contentHeight: rowsColumn.height + 2 * lay.pad
				clip: true
				// Each bar is decided from the outer size. Left to itself, a bar
				// that showed while the window was small takes room that keeps
				// it showing after the window has grown to fit.
				readonly property bool tall: contentHeight > height - (contentWidth > width ? ScrollBar.horizontal.implicitHeight : 0)
				readonly property bool wide: contentWidth > width - (tall ? ScrollBar.vertical.implicitWidth : 0)
				ScrollBar.vertical.policy: tall ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
				ScrollBar.horizontal.policy: wide ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

				Column {
					id: rowsColumn
					x: lay.pad
					y: lay.pad

					Repeater {
						model: win.rowsOf(win.current)
						delegate: settingRow
					}
				}
			}

			RowLayout {
				id: footer
				Layout.fillWidth: true
				Layout.margins: lay.pad
				Layout.topMargin: lay.buttons_gap
				spacing: lay.button_gap

				Item {
					Layout.fillWidth: true
				}
				Button {
					text: qsTr("&Cancel")
					Layout.minimumWidth: lay.button_width
					onClicked: win.cancel()
					ToolTip.text: decl.help.cancel
					ToolTip.visible: hovered && win.active
					ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
				}
				Button {
					text: qsTr("&Apply")
					Layout.minimumWidth: lay.button_width
					onClicked: win.apply()
					ToolTip.text: decl.help.apply
					ToolTip.visible: hovered && win.active
					ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
				}
				Button {
					text: qsTr("&OK")
					Layout.minimumWidth: lay.button_width
					onClicked: win.ok()
					ToolTip.text: decl.help.ok
					ToolTip.visible: hovered && win.active
					ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
				}
			}
		}
	}

	Component {
		id: settingRow

		Item {
			id: row
			required property var modelData
			readonly property var spec: modelData
			readonly property bool isHeading: spec.kind === "heading"
			// A field to try settings out in. It stores nothing.
			readonly property bool isTryout: spec.kind === "tryout"
			property string reason: ""
			property bool atDefault: true

			width: win.panelWidth
			height: win.heightOf(spec)
			visible: height > 0

			function refresh() {
				if (isHeading || isTryout)
					return
				reason = backend.unavailable(spec.name)
				atDefault = backend.isDefault(spec.name)
				if (control.item)
					control.item.sync()
			}
			Component.onCompleted: refresh()
			Connections {
				target: backend
				function onRevisionChanged() {
					row.refresh()
				}
			}

			// A grayed row explains why instead of what it does.
			readonly property string tip: reason !== "" ? reason : [spec.help, spec.warning].filter(t => t).join(" ")
			HoverHandler {
				id: hover
			}
			ToolTip.text: tip
			ToolTip.visible: tip !== "" && hover.hovered && win.active && win.popupsOpen === 0 && !revert.hovered && !testButton.hovered
			ToolTip.delay: Application.styleHints.mousePressAndHoldInterval

			// Heading: a title over a rule.
			Label {
				visible: row.isHeading
				anchors.bottom: rule.top
				anchors.bottomMargin: 3
				text: spec.label
				font.bold: true
			}
			Rectangle {
				id: rule
				visible: row.isHeading
				anchors.bottom: parent.bottom
				anchors.bottomMargin: 4
				width: parent.width
				height: 1
				color: win.palette.mid
			}

			// Only the label steps in. Every control keeps its column.
			Label {
				visible: !row.isHeading
				x: spec.indent * lay.indent
				anchors.bottom: parent.bottom
				height: win.rowHeight
				verticalAlignment: Text.AlignVCenter
				enabled: row.reason === ""
				text: spec.label + (spec.warning ? " " + decl.icons.warning : "")
			}

			Loader {
				id: control
				x: win.labelColumn
				anchors.bottom: parent.bottom
				height: win.rowHeight
				width: win.controlColumn
				enabled: row.reason === ""
				sourceComponent: ({ toggle: toggleControl, slider: sliderControl, dropdown: dropdownControl, text: textControl, tryout: tryoutControl })[spec.kind] || null
				onLoaded: item.sync()
			}

			ToolButton {
				id: testButton
				visible: spec.test !== ""
				x: win.labelColumn + win.controlColumn
				anchors.verticalCenter: control.verticalCenter
				width: lay.test_width
				focusPolicy: Qt.NoFocus
				enabled: row.reason === "" && !backend.testing
				contentItem: Label {
					text: decl.icons.test
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
				}
				onClicked: backend.testNow(spec.name)
				ToolTip.text: spec.test_help
				ToolTip.visible: hovered && win.active
				ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
			}

			ToolButton {
				id: revert
				visible: !row.isHeading && !row.isTryout
				x: win.labelColumn + win.controlColumn + lay.test_width
				anchors.verticalCenter: control.verticalCenter
				width: lay.revert_width
				focusPolicy: Qt.NoFocus
				enabled: !row.atDefault
				// Accent while there is something to put back, dim at the default.
				contentItem: Label {
					text: decl.icons.revert
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					color: row.atDefault ? win.palette.windowText : win.palette.highlight
					opacity: row.atDefault ? 0.35 : 1
				}
				onClicked: backend.revert(spec.name)
				ToolTip.text: decl.help.revert
				ToolTip.visible: hovered && win.active
				ToolTip.delay: Application.styleHints.mousePressAndHoldInterval
			}

			// Walking onto a field selects its value, so typing replaces it.
			function selectOnWalk(field) {
				if (field.activeFocus && (field.focusReason === Qt.TabFocusReason || field.focusReason === Qt.BacktabFocusReason))
					field.selectAll()
			}

			Component {
				id: toggleControl
				CheckBox {
					anchors.verticalCenter: parent ? parent.verticalCenter : undefined
					function sync() {
						checked = backend.value(spec.name) === true
					}
					onToggled: backend.setValue(spec.name, checked)
				}
			}

			Component {
				id: textControl
				TextField {
					anchors.verticalCenter: parent ? parent.verticalCenter : undefined
					width: lay.text_width
					function sync() {
						if (!activeFocus)
							text = backend.value(spec.name) ?? ""
					}
					onEditingFinished: backend.setValue(spec.name, text)
					onActiveFocusChanged: row.selectOnWalk(this)
				}
			}

			Component {
				id: tryoutControl
				TextField {
					anchors.verticalCenter: parent ? parent.verticalCenter : undefined
					width: lay.text_width
					placeholderText: spec.help
					function sync() {
					}
					onActiveFocusChanged: win.tryingKeys = activeFocus
				}
			}

			Component {
				id: dropdownControl
				ComboBox {
					anchors.verticalCenter: parent ? parent.verticalCenter : undefined
					model: spec.options
					implicitContentWidthPolicy: ComboBox.WidestText
					function sync() {
						currentIndex = backend.value(spec.name) ?? -1
					}
					onActivated: index => backend.setValue(spec.name, index)
					// Left and Right step through the options without opening.
					Keys.onLeftPressed: if (currentIndex > 0) backend.setValue(spec.name, currentIndex - 1)
					Keys.onRightPressed: if (currentIndex < count - 1) backend.setValue(spec.name, currentIndex + 1)
					popup.onVisibleChanged: win.popupsOpen += popup.visible ? 1 : -1
				}
			}

			Component {
				id: sliderControl
				Item {
					id: sliderBox
					readonly property real low: spec.min
					readonly property real high: spec.max
					property real pending: NaN

					function toTrack(v) {
						return spec.log ? Math.log(v / low) / Math.log(high / low) : v
					}
					function fromTrack(t) {
						return Math.round(spec.log ? low * Math.pow(high / low, t) : t)
					}
					function sync() {
						const v = backend.value(spec.name)
						if (typeof v !== "number")
							return
						if (!track.pressed)
							track.value = toTrack(v)
						if (!number.activeFocus)
							number.text = Math.round(v)
					}
					// A drag writes at most every tenth of a second, since each
					// write makes Wayfire reload its whole file.
					function send(v) {
						pending = Math.min(high, Math.max(low, v))
						number.text = pending
						if (!throttle.running)
							throttle.start()
					}
					function flush() {
						throttle.stop()
						if (!isNaN(pending))
							backend.setValue(spec.name, pending)
						pending = NaN
					}
					Timer {
						id: throttle
						interval: 100
						onTriggered: sliderBox.flush()
					}

					// About a hundredth of the range per step, a tenth with Shift,
					// and never less than one whole unit.
					function step(up, big) {
						const now = fromTrack(track.value)
						const unit = big ? 0.1 : 0.01
						let next
						if (spec.log)
							next = fromTrack(track.value + (up ? unit : -unit))
						else
							next = now + (up ? 1 : -1) * Math.max(1, Math.round((high - low) * unit))
						if (next === now)
							next = now + (up ? 1 : -1)
						send(next)
						flush()
					}

					Slider {
						id: track
						anchors.left: parent.left
						anchors.right: number.left
						anchors.rightMargin: 8
						anchors.verticalCenter: parent.verticalCenter
						from: spec.log ? 0 : sliderBox.low
						to: spec.log ? 1 : sliderBox.high
						onMoved: sliderBox.send(sliderBox.fromTrack(value))
						onPressedChanged: if (!pressed) sliderBox.flush()
						Keys.onPressed: event => {
							const up = event.key === Qt.Key_Up || event.key === Qt.Key_Right
							const down = event.key === Qt.Key_Down || event.key === Qt.Key_Left
							if (up || down) {
								sliderBox.step(up, event.modifiers & Qt.ShiftModifier)
								event.accepted = true
							}
						}
					}

					TextField {
						id: number
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						width: Math.max(lay.value_width, fm.advanceWidth(String(-Math.max(Math.abs(spec.min), Math.abs(spec.max)))) + leftPadding + rightPadding + 2)
						horizontalAlignment: TextInput.AlignRight
						validator: IntValidator {}
						onEditingFinished: {
							const v = parseInt(text)
							if (!isNaN(v)) {
								sliderBox.send(v)
								sliderBox.flush()
							}
						}
						onActiveFocusChanged: row.selectOnWalk(this)
					}
				}
			}
		}
	}
}
