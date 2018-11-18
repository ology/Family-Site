#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::SaltedHash;
use Family::Site::Schema;
use Term::ReadKey;
use YAML::XS 'LoadFile';

my $user = shift || die "Usage: perl $0 username\n";

my $config = LoadFile('config.yml');

my $db     = $config->{plugins}{Database}{database};
my $dbuser = $config->{plugins}{Database}{username};
my $dbpass = $config->{plugins}{Database}{password};

my $schema = Family::Site::Schema->connect( "dbi:mysql:dbname=$db", $dbuser, $dbpass );

# Show all users:
#my @rs = $schema->resultset('User')->search();
#print $_->username, "\n" for @rs;
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
    $entry->update;

    my $path = 'public/album';
    mkdir( "$path/$user" ) or die "Can't mkdir $path/$user: $!";
    open( my $fh, '>', "$path/$user/caption.txt" ) or die "Can't write $path/$user/caption.txt: $!";

    $schema->resultset('History')->create(
        {
            who  => $ENV{USER},
            what => 'new user: ' . $user,
            remote_addr => '127.0.0.1',
        }
    );
}
