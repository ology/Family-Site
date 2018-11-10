use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME         => 'Family::Site',
    AUTHOR       => q{Gene Boggs <gene@ology.net>},
    VERSION_FROM => 'lib/Family/Site.pm',
    ABSTRACT     => 'Family Social Network',
    ($eumm_version >= 6.3001
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML' => 0,
        'Crypt::SaltedHash' => 0,
        'Dancer' => 0,
        'Dancer::Plugin::Auth::Extensible' => 0,
        'Dancer::Plugin::DBIC' => 0,
        'Date::Manip' => 0,
        'DateTime' => 0,
        'DateTime::Duration' => 0,
        'DateTime::Format::DateParse' => 0,
        'Time::Ago' => 0,
        'File::Find::Rule' => 0,
        'Geo::IP::PurePerl' => 0,
        'HTML::CalendarMonthSimple' => 0,
        'IO::All' => 0,
        'Readonly' => 0,
        'Text::Unidecode' => 0,
        'URL::Search' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Family-Site-*' },
);
