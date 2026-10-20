/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

/// Social Clone is always a kiosk.
///
/// This fork exists for exactly one purpose — a locked-down TikTok /
/// Facebook multi-profile app — so the browser chrome upstream ships
/// (tab strip, address bar, toolbars, FAB) is never built here, and
/// the web content always gets the full screen. The flag exists so the
/// few upstream widgets that must know can ask one question in one
/// place instead of growing kiosk conditionals of their own.
const bool kKioskMode = true;
