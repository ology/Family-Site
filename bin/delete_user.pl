#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::SaltedHash;
use lib 'lib';
use Family::Site::Schema;
use File::Path qw( remove_tree );
use YAML::XS 'LoadFile';

my $user = shift || die "Usage: perl $0 username\n";

my $config = LoadFile('config.yml');

my $db     = $config->{plugins}{Database}{database};
my $dbuser = $config->{plugins}{Database}{username};
my $dbpass = $config->{plugins}{Database}{password};

my $schema = Family::Site::Schema->connect( "dbi:mysql:dbname=$db", $dbuser, $dbpass );

# Show all users:
#my @rs = $schema->resultset('User')->search();
#printf "%s (%d)\n", $_->username, $_->active for @rs;
#exit;

my $entry = $schema->resultset('User')->find( { username => $user } );

if ( $entry ) {
    $entry->delete;

    my $count = 0;
    my $path = "public/album/$user";
    if ( -d $path ) {
        $count = remove_tree($path);
    }

    $schema->resultset('History')->create(
        {
            who  => $ENV{USER},
            what => 'deleted: ' . $user . " ($count files removed)",
            remote_addr => '127.0.0.1',
        }
    );
}
else {
    die "User $user doesn't exist\n";
}
