// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! Times a "Test now" from the compositor's idle notices: the test starts once
//! the keyboard and mouse rest, and ends at the next key or mouse move. Its own
//! Wayland connection, on its own thread, so Qt's is left alone.

use std::time::{Duration, Instant};
use wayland_client::globals::{GlobalListContents, registry_queue_init};
use wayland_client::protocol::{wl_output, wl_registry, wl_seat};
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle, delegate_noop};
use wayland_protocols::ext::idle_notify::v1::client::{ext_idle_notification_v1, ext_idle_notifier_v1};
use wayland_protocols_wlr::output_power_management::v1::client::{zwlr_output_power_manager_v1, zwlr_output_power_v1};

#[derive(Default)]
struct State {
	idle: bool,
	back: bool,
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
	fn event(
		_: &mut Self,
		_: &wl_registry::WlRegistry,
		_: wl_registry::Event,
		_: &GlobalListContents,
		_: &Connection,
		_: &QueueHandle<Self>,
	) {
	}
}

impl Dispatch<ext_idle_notification_v1::ExtIdleNotificationV1, ()> for State {
	fn event(
		state: &mut Self,
		_: &ext_idle_notification_v1::ExtIdleNotificationV1,
		event: ext_idle_notification_v1::Event,
		(): &(),
		_: &Connection,
		_: &QueueHandle<Self>,
	) {
		match event {
			ext_idle_notification_v1::Event::Idled => state.idle = true,
			ext_idle_notification_v1::Event::Resumed => state.back = state.idle,
			_ => {}
		}
	}
}

delegate_noop!(State: ignore wl_seat::WlSeat);
delegate_noop!(State: ignore wl_output::WlOutput);
delegate_noop!(State: ext_idle_notifier_v1::ExtIdleNotifierV1);
delegate_noop!(State: zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1);
delegate_noop!(State: ignore zwlr_output_power_v1::ZwlrOutputPowerV1);

/// How a test goes.
pub struct Plan {
	/// Turn the screens off while idle, and back on after.
	pub blank: bool,
	/// How long the keyboard and mouse rest before the test starts.
	pub rest: Duration,
	/// No rest by then, and the test is called off.
	pub give_up: Duration,
}

/// Runs a test on a thread of its own, then calls `done` there, with why it
/// could not run if it could not.
pub fn run(plan: Plan, done: impl FnOnce(Result<(), String>) + Send + 'static) {
	std::thread::spawn(move || done(watch(&plan)));
}

fn watch(plan: &Plan) -> Result<(), String> {
	let conn = Connection::connect_to_env().map_err(|e| format!("No Wayland display to test on: {e}"))?;
	let (globals, mut queue) =
		registry_queue_init::<State>(&conn).map_err(|e| format!("The Wayland display did not answer: {e}"))?;
	let qh = queue.handle();
	let seat: wl_seat::WlSeat = globals
		.bind(&qh, 1..=1, ())
		.map_err(|_| "The compositor has no seat.".to_string())?;
	let notifier: ext_idle_notifier_v1::ExtIdleNotifierV1 = globals
		.bind(&qh, 1..=1, ())
		.map_err(|_| "The compositor does not say when the keyboard and mouse rest.".to_string())?;

	let mut powers = Vec::new();
	if plan.blank {
		let manager: zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1 = globals
			.bind(&qh, 1..=1, ())
			.map_err(|_| "The compositor does not let apps turn the screen off.".to_string())?;
		for global in globals.contents().clone_list() {
			if global.interface == "wl_output" {
				let output: wl_output::WlOutput = globals.registry().bind(global.name, 1, &qh, ());
				powers.push(manager.get_output_power(&output, &qh, ()));
			}
		}
	}

	let rest_ms = u32::try_from(plan.rest.as_millis()).unwrap_or(u32::MAX);
	let notice = notifier.get_idle_notification(rest_ms, &seat, &qh, ());
	let mut state = State::default();
	if wait(&mut queue, &mut state, |s| s.idle, Some(Instant::now() + plan.give_up))? {
		let mode = |on| {
			for power in &powers {
				power.set_mode(if on {
					zwlr_output_power_v1::Mode::On
				} else {
					zwlr_output_power_v1::Mode::Off
				});
			}
		};
		mode(false);
		let back = wait(&mut queue, &mut state, |s| s.back, None);
		// Back on even if the wait failed, so a screen is never left dark.
		mode(true);
		back?;
	}
	notice.destroy();
	queue.roundtrip(&mut state).map_err(|e| e.to_string())?;
	Ok(())
}

// Dispatches until `until` holds, or the deadline passes (false).
fn wait(
	queue: &mut EventQueue<State>,
	state: &mut State,
	until: impl Fn(&State) -> bool,
	deadline: Option<Instant>,
) -> Result<bool, String> {
	use rustix::event::{PollFd, PollFlags, Timespec, poll};
	loop {
		queue.dispatch_pending(state).map_err(|e| e.to_string())?;
		if until(state) {
			return Ok(true);
		}
		queue.flush().map_err(|e| e.to_string())?;
		let Some(guard) = queue.prepare_read() else {
			continue;
		};
		let left = deadline.map(|d| d.saturating_duration_since(Instant::now()));
		if left == Some(Duration::ZERO) {
			return Ok(false);
		}
		let timeout = left.map(|d| Timespec {
			tv_sec: d.as_secs() as _,
			tv_nsec: d.subsec_nanos().into(),
		});
		let ready = {
			let fd = guard.connection_fd();
			let mut fds = [PollFd::new(&fd, PollFlags::IN)];
			match poll(&mut fds, timeout.as_ref()) {
				Ok(n) => n > 0,
				Err(rustix::io::Errno::INTR) => false,
				Err(e) => return Err(e.to_string()),
			}
		};
		if ready {
			guard.read().map_err(|e| e.to_string())?;
		}
	}
}
