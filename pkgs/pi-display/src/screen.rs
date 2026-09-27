use embedded_graphics::mono_font::MonoTextStyle;
use embedded_graphics::mono_font::iso_8859_1::{FONT_7X13, FONT_7X13_BOLD};
use embedded_graphics::pixelcolor::BinaryColor;
use embedded_graphics::prelude::*;
use embedded_graphics::primitives::{PrimitiveStyle, Triangle};
use embedded_graphics::text::{Alignment, Baseline, Text, TextStyle, TextStyleBuilder};
use jiff::{Unit, Zoned};

use crate::air::{Air, Direction};
use crate::icons::{self, Icon};
use crate::tram::{self, Departure};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mood {
    Good,
    Fair,
    Poor,
}

impl Mood {
    fn of(iaq: f64) -> Self {
        match iaq {
            ..=100.0 => Mood::Good,
            ..=200.0 => Mood::Fair,
            _ => Mood::Poor,
        }
    }

    fn icon(self) -> &'static Icon {
        match self {
            Mood::Good => &icons::FACE_GOOD,
            Mood::Fair => &icons::FACE_FAIR,
            Mood::Poor => &icons::FACE_POOR,
        }
    }
}

/// What the screen shows, as text; drawing is a separate step.
#[derive(Debug, PartialEq)]
pub struct Layout {
    pub tram: String,
    pub tram_when: String,
    pub next: String,
    pub mood: Mood,
    pub iaq: String,
    pub trend: Option<Direction>,
    pub temperature: String,
    pub humidity: String,
    pub clock: String,
}

pub struct Inputs<'a> {
    pub departures: Option<&'a [Departure]>,
    pub trams_stale: bool,
    pub air: Option<&'a Air>,
    pub trend: Option<Direction>,
}

enum When {
    Now,
    Minutes(i64),
    Clock(String),
}

fn when(departure: &Departure, now: &Zoned) -> When {
    let minutes = (&departure.time - now)
        .total(Unit::Minute)
        .map_or(0.0, |m| m.floor()) as i64;
    match minutes {
        ..=0 => When::Now,
        1..=60 => When::Minutes(minutes),
        _ => When::Clock(departure.time.strftime("%H:%M").to_string()),
    }
}

impl When {
    fn full(&self) -> String {
        match self {
            When::Now => "now".into(),
            When::Minutes(m) => format!("{m} min"),
            When::Clock(c) => c.clone(),
        }
    }
}

/// "then 18, 33 min" when both are minutes, each item in full otherwise.
fn then(later: &[When]) -> String {
    if later.is_empty() {
        return String::new();
    }
    let items: Vec<String> = if later.iter().all(|w| matches!(w, When::Minutes(_))) {
        let mut items: Vec<String> = later
            .iter()
            .map(|w| match w {
                When::Minutes(m) => m.to_string(),
                _ => unreachable!(),
            })
            .collect();
        if let Some(last) = items.last_mut() {
            last.push_str(" min");
        }
        items
    } else {
        later.iter().map(When::full).collect()
    };
    format!("then {}", items.join(", "))
}

pub fn layout(inputs: &Inputs, now: &Zoned) -> Layout {
    let (tram, mut tram_when, next) = match inputs.departures {
        None => ("No tram data".into(), String::new(), String::new()),
        Some(deps) => {
            let upcoming = tram::upcoming(deps, now.timestamp());
            let mut running = upcoming.iter().filter(|d| !d.cancelled);
            match running.next() {
                None => ("No departures".into(), String::new(), String::new()),
                Some(first) => {
                    let next = match upcoming.first() {
                        Some(d) if d.cancelled => {
                            format!("{} cancelled", d.time.strftime("%H:%M"))
                        }
                        _ => then(&running.take(2).map(|d| when(d, now)).collect::<Vec<_>>()),
                    };
                    (first.direction.clone(), when(first, now).full(), next)
                }
            }
        }
    };
    if inputs.trams_stale && !tram_when.is_empty() {
        tram_when.push('?');
    }

    let air = inputs.air.cloned().unwrap_or_default();
    Layout {
        tram,
        tram_when,
        next,
        mood: air.iaq.map_or(Mood::Fair, Mood::of),
        iaq: air.iaq.map_or("IAQ --".into(), |v| format!("IAQ {v:.0}")),
        trend: air.iaq.and(inputs.trend),
        temperature: air
            .temperature
            .map_or("--.-°".into(), |t| format!("{t:.1}°")),
        humidity: air.humidity.map_or("--%".into(), |h| format!("{h:.0}%")),
        clock: now.strftime("%H:%M").to_string(),
    }
}

const EDGE: i32 = 125;
const ROW_Y: [i32; 4] = [0, 15, 31, 47];
const GAP: i32 = 3;

fn text<D>(
    target: &mut D,
    s: &str,
    at: Point,
    font: MonoTextStyle<'_, BinaryColor>,
    style: TextStyle,
) -> Result<(), D::Error>
where
    D: DrawTarget<Color = BinaryColor>,
{
    Text::with_text_style(s, at, font, style)
        .draw(target)
        .map(drop)
}

/// Draws an icon, vertically centred on a 13 px text row, and returns the x
/// where the following text starts.
fn icon<D>(target: &mut D, icon: &Icon, x: i32, row: usize, offset: Point) -> Result<i32, D::Error>
where
    D: DrawTarget<Color = BinaryColor>,
{
    icons::draw(target, icon, offset + Point::new(x, ROW_Y[row] + 1))?;
    Ok(x + icons::width(icon) + GAP)
}

pub fn draw<D>(target: &mut D, layout: &Layout, offset: Point) -> Result<(), D::Error>
where
    D: DrawTarget<Color = BinaryColor>,
{
    let bold = MonoTextStyle::new(&FONT_7X13_BOLD, BinaryColor::On);
    let medium = MonoTextStyle::new(&FONT_7X13, BinaryColor::On);
    let left = TextStyleBuilder::new().baseline(Baseline::Top).build();
    let right = TextStyleBuilder::new()
        .baseline(Baseline::Top)
        .alignment(Alignment::Right)
        .build();
    let at = |x: i32, row: usize| offset + Point::new(x, ROW_Y[row]);

    let x = icon(target, &icons::TRAM, 0, 0, offset)?;
    let when_width = layout.tram_when.chars().count() as i32 * 7;
    let room = ((EDGE - x - when_width - GAP) / 7).max(0) as usize;
    let tram: String = layout.tram.chars().take(room).collect();
    text(target, &tram, at(x, 0), bold, left)?;
    text(target, &layout.tram_when, at(EDGE, 0), bold, right)?;

    let next_width = layout.next.chars().count() as i32 * 7;
    let next_x = if x + next_width <= EDGE { x } else { 0 };
    text(target, &layout.next, at(next_x, 1), medium, left)?;

    let x = icon(target, layout.mood.icon(), 0, 2, offset)?;
    text(target, &layout.iaq, at(x, 2), medium, left)?;
    if let Some(direction) = layout.trend {
        let x = x + layout.iaq.chars().count() as i32 * 7 + 2;
        let y = ROW_Y[2];
        let (tip, base) = match direction {
            Direction::Up => (y + 3, y + 9),
            Direction::Down => (y + 9, y + 3),
        };
        Triangle::new(
            offset + Point::new(x + 3, tip),
            offset + Point::new(x, base),
            offset + Point::new(x + 6, base),
        )
        .into_styled(PrimitiveStyle::with_fill(BinaryColor::On))
        .draw(target)?;
    }
    let temp_width = layout.temperature.chars().count() as i32 * 7;
    let temp_x = EDGE - temp_width;
    icon(
        target,
        &icons::THERMOMETER,
        temp_x - icons::width(&icons::THERMOMETER) - GAP,
        2,
        offset,
    )?;
    text(target, &layout.temperature, at(EDGE, 2), medium, right)?;

    let x = icon(target, &icons::DROP, 0, 3, offset)?;
    text(target, &layout.humidity, at(x, 3), medium, left)?;
    let clock_width = layout.clock.chars().count() as i32 * 7;
    let clock_x = EDGE - clock_width;
    icon(
        target,
        &icons::CLOCK,
        clock_x - icons::width(&icons::CLOCK) - GAP,
        3,
        offset,
    )?;
    text(target, &layout.clock, at(EDGE, 3), medium, right)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use jiff::civil::DateTime;
    use jiff::tz::TimeZone;

    use super::*;

    fn at(local: &str) -> Zoned {
        local
            .parse::<DateTime>()
            .unwrap()
            .to_zoned(TimeZone::get("Europe/Copenhagen").unwrap())
            .unwrap()
    }

    fn departure(local: &str, direction: &str, cancelled: bool) -> Departure {
        Departure {
            line: "L2".into(),
            direction: direction.into(),
            time: at(local),
            cancelled,
        }
    }

    fn air() -> Air {
        Air {
            iaq: Some(152.4),
            temperature: Some(24.25),
            humidity: Some(45.6),
        }
    }

    fn inputs<'a>(deps: &'a [Departure], air: &'a Air) -> Inputs<'a> {
        Inputs {
            departures: Some(deps),
            trams_stale: false,
            air: Some(air),
            trend: Some(Direction::Up),
        }
    }

    #[test]
    fn next_tram_in_minutes_then_the_two_after() {
        let deps = [
            departure("2026-09-28T08:03:00", "Aarhus H", false),
            departure("2026-09-28T08:18:00", "Aarhus H", false),
            departure("2026-09-28T08:33:00", "Odder", false),
            departure("2026-09-28T08:48:00", "Aarhus H", false),
        ];
        let air = air();
        let l = layout(&inputs(&deps, &air), &at("2026-09-28T08:00:30"));
        assert_eq!(l.tram, "Aarhus H");
        assert_eq!(l.tram_when, "2 min");
        assert_eq!(l.next, "then 17, 32 min");
        assert_eq!(l.mood, Mood::Fair);
        assert_eq!(l.iaq, "IAQ 152");
        assert_eq!(l.trend, Some(Direction::Up));
        assert_eq!(l.temperature, "24.2°");
        assert_eq!(l.humidity, "46%");
        assert_eq!(l.clock, "08:00");
    }

    #[test]
    fn long_waits_show_the_clock_time() {
        let deps = [
            departure("2026-09-28T00:54:00", "Aarhus H", false),
            departure("2026-09-28T01:09:00", "Aarhus H", false),
            departure("2026-09-28T05:24:00", "Aarhus H", false),
        ];
        let air = air();
        let l = layout(&inputs(&deps, &air), &at("2026-09-28T00:50:00"));
        assert_eq!(l.tram_when, "4 min");
        assert_eq!(l.next, "then 19 min, 05:24");
        let l = layout(&inputs(&deps, &air), &at("2026-09-28T01:09:20"));
        assert_eq!(l.tram_when, "05:24");
        assert_eq!(l.next, "");
    }

    #[test]
    fn departing_now() {
        let deps = [departure("2026-09-28T08:00:50", "Aarhus H", false)];
        let air = air();
        let l = layout(&inputs(&deps, &air), &at("2026-09-28T08:00:10"));
        assert_eq!(l.tram_when, "now");
    }

    #[test]
    fn a_cancelled_next_tram_is_reported_and_skipped() {
        let deps = [
            departure("2026-09-28T08:03:00", "Aarhus H", true),
            departure("2026-09-28T08:18:00", "Aarhus H", false),
        ];
        let air = air();
        let l = layout(&inputs(&deps, &air), &at("2026-09-28T08:00:00"));
        assert_eq!(l.tram_when, "18 min");
        assert_eq!(l.next, "08:03 cancelled");
    }

    #[test]
    fn mood_follows_iaq_categories() {
        assert_eq!(Mood::of(100.0), Mood::Good);
        assert_eq!(Mood::of(100.5), Mood::Fair);
        assert_eq!(Mood::of(200.0), Mood::Fair);
        assert_eq!(Mood::of(250.0), Mood::Poor);
    }

    #[test]
    fn missing_and_stale_data_are_marked() {
        let deps = [departure("2026-09-28T08:03:00", "Aarhus H", false)];
        let air = Air { iaq: None, ..air() };
        let l = layout(
            &Inputs {
                departures: Some(&deps),
                trams_stale: true,
                air: Some(&air),
                trend: Some(Direction::Down),
            },
            &at("2026-09-28T08:00:00"),
        );
        assert_eq!(l.tram_when, "3 min?");
        assert_eq!(l.iaq, "IAQ --");
        assert_eq!(l.trend, None);

        let l = layout(
            &Inputs {
                departures: None,
                trams_stale: true,
                air: None,
                trend: None,
            },
            &at("2026-09-28T08:00:00"),
        );
        assert_eq!(l.tram, "No tram data");
        assert_eq!(l.tram_when, "");
        assert_eq!(l.temperature, "--.-°");
        assert_eq!(l.humidity, "--%");
    }

    /// A 128×64 target that records pixels drawn outside the panel.
    #[derive(Default)]
    struct Panel {
        outside: Vec<Point>,
    }

    impl OriginDimensions for Panel {
        fn size(&self) -> Size {
            Size::new(128, 64)
        }
    }

    impl DrawTarget for Panel {
        type Color = BinaryColor;
        type Error = Infallible;

        fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Infallible>
        where
            I: IntoIterator<Item = Pixel<BinaryColor>>,
        {
            for Pixel(p, _) in pixels {
                if !(0..128).contains(&p.x) || !(0..64).contains(&p.y) {
                    self.outside.push(p);
                }
            }
            Ok(())
        }
    }

    #[test]
    fn widest_content_fits_the_panel() {
        let layout = Layout {
            tram: "Lisbjergskolen".into(),
            tram_when: "59 min?".into(),
            next: "then 59 min, 23:59".into(),
            mood: Mood::Poor,
            iaq: "IAQ 500".into(),
            trend: Some(Direction::Down),
            temperature: "-10.0°".into(),
            humidity: "100%".into(),
            clock: "23:59".into(),
        };
        for offset in [Point::zero(), Point::new(2, 2)] {
            let mut panel = Panel::default();
            draw(&mut panel, &layout, offset).unwrap();
            assert!(panel.outside.is_empty(), "{offset:?}: {:?}", panel.outside);
        }
    }
}
