// GENERATED DATA. Bikram Sambat (BS) month lengths for BS 2070-2086.
// Source: nepali-date-system (MIT), which takes 1975-2083 from rjach/sambat
// calendar.csv (Apache-2.0, cross-checked against about 20 open-source tables;
// 2081-2083 verified against published panchangs). 2084-2086 are PROVISIONAL
// (they match Hamro Patro and four other converters) until the official
// calendar is published. Checked: 2070-2083 are identical in 5 independent
// tables. Month lengths are calendar facts; attribution is kept for transparency.

/// First year in [bsMonthLengths].
const int bsFirstYear = 2070;

/// Last year whose calendar is officially published.
const int bsLastOfficialYear = 2083;

/// Last year in the table (2084-2086 are provisional estimates).
const int bsLastYear = 2086;

/// AD date of 1 Baisakh 2070 (day 0 of the table).
final DateTime bsFirstYearStartAd = DateTime(2013, 4, 14);

/// Row = year - bsFirstYear, column = month - 1 (Baisakh .. Chaitra).
const List<List<int>> bsMonthLengths = [
  /* 2070 */ [31, 31, 31, 32, 31, 31, 29, 30, 30, 29, 30, 30],
  /* 2071 */ [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2072 */ [31, 32, 31, 32, 31, 30, 30, 29, 30, 29, 30, 30],
  /* 2073 */ [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 31],
  /* 2074 */ [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2075 */ [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2076 */ [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
  /* 2077 */ [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
  /* 2078 */ [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2079 */ [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2080 */ [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
  /* 2081 */ [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
  /* 2082 */ [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2083 */ [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
  /* 2084 */ [31, 31, 32, 31, 31, 30, 30, 30, 29, 30, 30, 30],
  /* 2085 */ [31, 32, 31, 32, 30, 31, 30, 30, 29, 30, 30, 30],
  /* 2086 */ [30, 32, 31, 32, 31, 30, 30, 30, 29, 30, 30, 30]
];
