#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::SaltedHash;
use Family::Site::Schema;
use Term::ReadKey;
use YAML::XS 'LoadFile';

my $db   = shift || die usage();
my $user = shift || die usage();

my $config = LoadFile('config.yml');

my $dbuser = $config->{plugins}{Database}{username};
my $dbpass = $config->{plugins}{Database}{password};

my $schema = Family::Site::Schema->connect( "dbi:mysql:dbname=$db", $dbuser, $dbpass );

# Show all users:
#my @rs = $schema->resultset('User')->search();
#print $_->username, "\n" for @rs;
#exit;

my $entry = $schema->resultset('User')->find( { username => $user } );

if ( $entry ) {
    ReadMode('noecho');
    print "Password for $user user: ";
    my $pass = ReadLine(0);
    chomp $pass;
    print "\n";
    ReadMode('restore');

    my $csh = Crypt::SaltedHash->new( algorithm => 'SHA-1' );
    $csh->add($pass);
    my $encrypted = $csh->generate;

    $entry->password($encrypted);
    $entry->active(0);
    $entry->update;

    $schema->resultset('History')->create(
        {
            who  => $ENV{USER},
            what => 'reset password for: ' . $user,
        }
    );
}
else {
    die "User $user doesn't exist";
}

sub usage {
    "Usage: perl $0 database username";
}
