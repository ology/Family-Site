#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::SaltedHash;
use Family::Site::Schema;
use Term::ReadKey;

my $db   = shift || die usage();
my $user = shift || die usage();

my $schema = Family::Site::Schema->connect( "dbi:mysql:dbname=$db", 'root', 'abc123' );

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
    $entry->active(1);
    $entry->update;

    my $path = 'public/album';
    mkdir( "$path/$user" ) or die "Can't mkdir $path/$user: $!";
    open( my $fh, '>', "$path/$user/caption.txt" ) or die "Can't write $path/$user/caption.txt: $!";
}

sub usage {
    "Usage: perl $0 database username";
}
