#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::SaltedHash;
use lib 'lib';
use Family::Site::Schema;
use Term::ReadKey;
use YAML::XS 'LoadFile';

my $user     = shift || die "Usage: perl $0 Username [is_admin]\n";
my $is_admin = shift || 0;

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
    die "User $user already present";
}
else {
    ReadMode('noecho');
    print "Password for $user user: ";
    my $pass = ReadLine(0);
    chomp $pass;
    print "\n";
    ReadMode('restore');

    my $csh = Crypt::SaltedHash->new( algorithm => 'SHA-1' );
    $csh->add($pass);
    my $encrypted = $csh->generate;

    my $entry = $schema->resultset('User')->create({ username => $user });

    $entry->password($encrypted);

    $entry->admin(1) if $is_admin;

    $entry->update;

    $schema->resultset('Address')->create( { first_name => $user } );

    my $path = 'public/album';
    mkdir( "$path/$user" ) or warn "Can't mkdir $path/$user: $!";
    open( my $fh, '>', "$path/$user/caption.txt" ) or warn "Can't write $path/$user/caption.txt: $!";

    $schema->resultset('History')->create(
        {
            who  => $ENV{USER},
            what => 'new user: ' . $user,
            remote_addr => '127.0.0.1',
        }
    );
}
