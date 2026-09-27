use embedded_graphics::Pixel;
use embedded_graphics::pixelcolor::BinaryColor;
use embedded_graphics::prelude::*;

pub type Icon = [&'static str; 11];

pub const TRAM: Icon = [
    ".....###.....",
    "......#......",
    ".###########.",
    "#...........#",
    "#.##.##.##..#",
    "#.##.##.##..#",
    "#...........#",
    "#...........#",
    ".###########.",
    "..##.....##..",
    "..##.....##..",
];

pub const FACE_GOOD: Icon = face("#.#.....#.#", "#..#####..#");
pub const FACE_FAIR: Icon = face("#.........#", "#..#####..#");
pub const FACE_POOR: Icon = face("#..#####..#", "#.#.....#.#");

const fn face(mouth_top: &'static str, mouth_bottom: &'static str) -> Icon {
    [
        "...#####...",
        ".##.....##.",
        ".#.......#.",
        "#..#...#..#",
        "#.........#",
        "#.........#",
        mouth_top,
        mouth_bottom,
        ".#.......#.",
        ".##.....##.",
        "...#####...",
    ]
}

#[rustfmt::skip]
pub const THERMOMETER: Icon = [
    "..###..",
    ".#...#.",
    ".#.#.#.",
    ".#.#.#.",
    ".#.#.#.",
    ".#.#.#.",
    "#..#..#",
    "#.###.#",
    "#.###.#",
    "#.....#",
    ".#####.",
];

#[rustfmt::skip]
pub const DROP: Icon = [
    "...#...",
    "...#...",
    "..#.#..",
    "..#.#..",
    ".#...#.",
    ".#...#.",
    "#.....#",
    "#.#...#",
    "#..#..#",
    ".#...#.",
    "..###..",
];

pub const CLOCK: Icon = [
    "...#####...",
    ".##.....##.",
    ".#...#...#.",
    "#....#....#",
    "#....#....#",
    "#....####.#",
    "#.........#",
    "#.........#",
    ".#.......#.",
    ".##.....##.",
    "...#####...",
];

pub fn width(icon: &Icon) -> i32 {
    icon[0].len() as i32
}

pub fn draw<D>(target: &mut D, icon: &Icon, top_left: Point) -> Result<(), D::Error>
where
    D: DrawTarget<Color = BinaryColor>,
{
    target.draw_iter(icon.iter().enumerate().flat_map(|(y, row)| {
        row.bytes()
            .enumerate()
            .filter(|&(_, c)| c == b'#')
            .map(move |(x, _)| Pixel(top_left + Point::new(x as i32, y as i32), BinaryColor::On))
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_have_equal_width() {
        for icon in [
            TRAM,
            FACE_GOOD,
            FACE_FAIR,
            FACE_POOR,
            THERMOMETER,
            DROP,
            CLOCK,
        ] {
            assert!(icon.iter().all(|r| r.len() == icon[0].len()), "{icon:?}");
        }
    }
}
