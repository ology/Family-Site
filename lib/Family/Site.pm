package Family::Site;

# ABSTRACT: Family::Site

our $VERSION = '0.21';

use Crypt::SaltedHash;
use Dancer qw( :syntax );
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC qw( schema resultset );
use Date::Manip;
use DateTime;
use DateTime::Duration;
use DateTime::Format::DateParse;
use Time::Ago;
use File::Find::Rule;
use Geo::IP::PurePerl;
use HTML::CalendarMonthSimple;
use IO::All -utf8;
use Readonly;
use Text::Unidecode;
use URL::Search qw( partition_urls );

Readonly my $FILE    => 'chat.txt';
Readonly my $CAPTION => 'caption.txt';
Readonly my $ALBUM   => 'public/album';
Readonly my $GEODAT  => '/home/gene/geoip/GeoLiteCity.dat';
Readonly my $PWSIZE  => 6;
Readonly my $TZ      => 'America/Los_Angeles';

sub is_blocked {
    my ($remote_address) = @_;
    return schema->resultset('Ban')->search( { ip => $remote_address } )->count ? 1 : 0;
}

get '/ban' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $record;
    my $records;
    my @sorted;

    if ( params->{id} ) {
        # Get the current entry
        my $entry = schema->resultset('Ban')->find( { id => params->{id} } );

        # Set the record of the current entry, to display
        $record = {
            id        => $entry->id,
            ip        => $entry->ip,
            last_seen => $entry->last_seen,
        } if $entry;
    }
    else {
        # Collect entries
        my $results = schema->resultset('Ban')->search( {}, { order_by => { -asc => 'last_seen' } } );
        while ( my $result = $results->next ) {
            push @sorted, $result->id;
            $records->{ $result->id } =
                {
                    id        => $result->id,
                    ip        => $result->ip,
                    last_seen => $result->last_seen,
                };
        }
    }

    template 'ban', {
        entry  => $record,
        data   => $records,
        sorted => \@sorted,
        method => params->{id} ? 'update' : 'add',
    };
};

post '/block' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) if $user->{username} ne 'gene';

    my $now = DateTime->now( time_zone => $TZ )->ymd
        . ' ' . DateTime->now( time_zone => $TZ )->hms;

    my $id = params->{id};
    $id =~ s/\D//g;

    my $ip = params->{ip};
    $ip =~ s/[^\d.]//g;

    my $last_seen = params->{last_seen};
    $last_seen =~ s/[^\dT:-]//g;

    # Create a new entry
    if ( params->{add} && $ip ) {
        schema->resultset('Ban')->create(
            {
                ip        => $ip,
                last_seen => $now,
            }
        );

#        _add_history(
#            who  => $user->{username},
#            what => "ban $ip",
#        );
    }

    # Get the current entry
    my $entry = schema->resultset('Ban')->find( { id => $id } );

    # Update the entry
    if ( $entry && params->{update} ) {
        $entry->ip($ip);
        $entry->last_seen($last_seen);
        $entry->update;

#        _add_history(
#            who  => $user->{username},
#            what => "update $ip ban",
#        );
    }

    # Delete the entry
    if ( $entry && params->{delete} ) {
        $entry->delete;

#        _add_history(
#            who  => $user->{username},
#            what => "delete $ip ban",
#        );
    }

    # Set the record of the current entry, to display
    my $record;
    if ( $entry && !params->{update} ) {
        $record = {
            id        => $entry->id,
            ip        => $entry->ip,
            last_seen => $entry->last_seen,
        };
    }

    redirect '/ban';
    halt;
};

get '/' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current user
    my $user  = logged_in_user;
    my $entry = schema->resultset('User')->find( { username => $user->{username} } );

    # Redirect to set a new password if they are not active
    if ( !$entry->active ) {
        redirect 'password';
        halt;
    }

    # Log the user presence
    my $now = DateTime->now( time_zone => $TZ )->ymd
        . ' ' . DateTime->now( time_zone => $TZ )->hms;
    $entry->last_login($now);
    $entry->remote_addr( request->remote_address );
    $entry->update;

    # Set the number of chat posts ("lines") to show
    my $lines = params->{lines} || 100;

    # Set the content to show, to the chat posts
    my @content;
    if ( -e $FILE ) {
        my $counter = 0;
        my $io = io($FILE);
        $io->backwards;
        while( defined( my $line = $io->getline ) ) {
            last if ++$counter > $lines;
            my ( $who, $when, $what ) = ( $line =~ /^(\w+) ([ \d:-]+): (.*)$/ );
            my $formatted = sprintf '<b>%s</b> <span class="smallstamp">%s:</span> %s',
                $who, $when, $what;
            push @content, '<p class="padding">' . $formatted . '</p>';
        }
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Collect the events for the current month
    my @cal;
    my $events = schema->resultset('Calendar')->search( { month => $MONTH }, { order_by => 'day' } );
    while ( my $result = $events->next ) {
        push @cal, {
            title => $result->title,
            month => $result->month,
            day   => $result->day,
            note  => $result->note,
        };
    }
    my @important;
    $events = schema->resultset('Calendar')->search( { important => 1, month => { '!=' => $MONTH } }, { order_by => { -asc => [qw( month day )]  } } );
    while ( my $result = $events->next ) {
        push @important, {
            title => $result->title,
            month => $result->month,
            day   => $result->day,
            note  => $result->note,
        };
    }

    # Redirect to the main site template
    template 'index', {
        user      => $user->{username},
        chat      => \@content,
        lines     => $lines,
        cal       => \@cal,
        important => \@important,
        month     => $MONTH,
        year      => $YEAR,
    };
};

post '/chat' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current user
    my $user  = logged_in_user;

    # Set the chat parameters
    my $text  = defined params->{text} ? params->{text} : '';
    my $stamp = params->{stamp} || 1;

    # Trim the text
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;

    # Append any user text to the chat file
    if ( defined $text && $text ne '' ) {
        my $now = DateTime->now( time_zone => $TZ )->ymd
            . ' ' . DateTime->now( time_zone => $TZ )->hms;
        my $html = '';
        for my $part ( partition_urls $text ) {
            my ( $type, $str ) = @$part;
            if ( $type eq 'URL' ) {
                $html .= "<a href='$str'>$str</a>";
            } else {
                $html .= $str;
            }
        }
        $text = $html;

        $text = unidecode($text);

        $text = sprintf '%s %s: %s',
            $user->{username},
            ( $stamp ? ' ' . $now : '' ),
            $text;
        $text =~ s/\n/<br\/>/g;

        "$text\n" >> io($FILE);

#        _add_history(
#            who  => $user->{username},
#            what => 'add ', length($text), ' chars to chat',
#        );
    }

    # Return to the main page
    redirect '/';
    halt;
};

get '/password' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );
    template 'password';
};

post '/password_set' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the new passwords from the form
    my $new_pwd   = params->{new_password};
    my $new_again = params->{new_password_again};

    # If we are valid...
    if ( $new_pwd && $new_again && length($new_pwd) >= $PWSIZE && $new_pwd eq $new_again ) {
        # Encrypt the password
        my $csh = Crypt::SaltedHash->new( algorithm => 'SHA-1' );
        $csh->add($new_pwd);
        my $encrypted = $csh->generate;

        # Update the user database entry
        my $user  = logged_in_user;
        my $entry = schema->resultset('User')->find( { username => $user->{username} } );
        $entry->password($encrypted);
        $entry->active(1);
        $entry->update;

#        _add_history(
#            who  => $user->{username},
#            what => 'reset password',
#        );

        # Return to the main page
        redirect '/';
        halt;
    }
    else {
        send_error( 'Invalid password', 400 );
    }
};

get '/log' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Collect the user records
    my $records;
    my $users = schema->resultset('User')->search( { last_login => { '!=' => undef } } );
    while ( my $result = $users->next ) {
        $records->{ $result->id } = {
            username    => $result->username,
            last_login  => $result->last_login->ymd . ' ' . $result->last_login->hms,
            remote_addr => $result->remote_addr,
        };
    }

    # Instantiate a geo-ip object
    my $gi = Geo::IP::PurePerl->new( $GEODAT, GEOIP_STANDARD );

    # Create a sorted list of seen users
    my @sorted;

    my $now = DateTime->now( time_zone => $TZ );

    for my $record ( sort { $records->{$b}{last_login} cmp $records->{$a}{last_login} } keys %$records ) {
        # Skip anyone who has not logged-in
        next unless $records->{$record}{last_login};

        # Find the time ago, since last_login
        my $last_login = DateTime::Format::DateParse->parse_datetime( $records->{$record}{last_login}, 'local' );
        my $duration   = $now->subtract_datetime_absolute($last_login);
        my $seconds    = $duration->seconds();
        $records->{$record}{ago} = ucfirst( Time::Ago->in_words($seconds) );

        # Compute the last seen location
        if ( $records->{$record}{remote_addr} ) {
            my @location = $gi->get_city_record( $records->{$record}{remote_addr} );
            my $location = @location
                ? join( ', ', grep { $_ ne '' } @location[ 4, 3, 2 ] )
                : $records->{$record}{remote_addr};
            $location =~ s/, United States//;
            $records->{$record}{location} = $location;
        }

        # Add the record to the sorted list
        push @sorted, $records->{$record};
    }

    # Get the last line of the chat
    my $last = '';
    if ( -e $FILE ) {
        my $io = io($FILE);
        $io->backwards;
        while( defined( my $line = $io->getline ) ) {
            $last = $line;
            last;
        }
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Collect the events for the current month
    my @cal;
    my $events = schema->resultset('Calendar')->search( { month => $MONTH }, { order_by => 'day' } );
    while ( my $result = $events->next ) {
        push @cal, {
            title => $result->title,
            month => $result->month,
            day   => $result->day,
        };
    }

    # Get the total number of calendar events
    my $total = schema->resultset('Calendar')->count();

    # Collect the album files to display
    my @files = File::Find::Rule->file()->in($ALBUM);
    @files = grep { !/\.txt$/ } @files;
    my @mtimes = map { { name => $_, mtime => (stat $_)[9] } } @files;
    @files = map { $_->{name} } sort { $b->{mtime} <=> $a->{mtime} } @mtimes;
    @files = map { s/^public\/(.*)$/$1/r } @files;

    # Count the addresses
    my $addresses = schema->resultset('Address')->count();

    # Count the recipes
    my $recipes = schema->resultset('Cookbook')->count();

    # Count the banned IPs
    my $bans = schema->resultset('Ban')->count;

    # Redirect to the log page
    template 'log', {
        line    => $last,
        sorted  => \@sorted,
        cal     => \@cal,
        files   => \@files,
        addr    => $addresses,
        recipes => $recipes,
        bans    => $bans,
        calnum  => $total,
        month   => $MONTH,
        year    => $YEAR,
    };
};

get '/addressbook' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current entry
    my $entry = schema->resultset('Address')->find( { id => params->{id} } );

    # Set the record of the current entry, to display
    my $record;
    if ($entry) {
        $record = {
            id         => $entry->id,
            first_name => $entry->first_name,
            last_name  => $entry->last_name,
            street     => $entry->street,
            city       => $entry->city,
            state      => $entry->state,
            zip        => $entry->zip,
            phone      => $entry->phone,
            phone2     => $entry->phone2,
            email      => $entry->email,
            notes      => $entry->notes,
            $entry->birthday ? ( birthday => $entry->birthday->ymd ) : (),
        };
    }

    # Collect all entries
    my $records;
    my @sorted;
    my $results = schema->resultset('Address')->search( undef, { order_by => { -asc => [ 'last_name', 'first_name' ] } } );
    while ( my $result = $results->next ) {
        push @sorted, $result->id;
        $records->{ $result->id } =
            {
                id         => $result->id,
                first_name => $result->first_name,
                last_name  => $result->last_name,
                street     => $result->street,
                city       => $result->city,
                state      => $result->state,
                zip        => $result->zip,
                phone      => $result->phone,
                phone2     => $result->phone2,
                email      => $result->email,
                notes      => $result->notes,
                $result->birthday ? ( birthday => $result->birthday->ymd ) : (),
            };
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Redirect to the addressbook page
    template 'addressbook', {
        edit   => $record,
        data   => $records,
        sorted => \@sorted,
        method => params->{id} ? 'update' : 'add',
        month  => $MONTH,
        year   => $YEAR,
    };
};

post '/address' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current user
    my $user  = logged_in_user;

    # Parse the birthday, if given
    my $birthday;
    if ( params->{birthday} ) {
        $birthday = ParseDate( params->{birthday} );
        $birthday = join '-', UnixDate( $birthday, "%Y", "%m", "%d" );
    }

    # Create a new entry
    if ( params->{add} && params->{first_name} ) {
        schema->resultset('Address')->create(
            {
                first_name => params->{first_name},
                last_name  => params->{last_name},
                street     => params->{street},
                city       => params->{city},
                state      => params->{state},
                zip        => params->{zip},
                phone      => params->{phone},
                phone2     => params->{phone2},
                email      => params->{email},
                notes      => params->{notes},
                birthday   => $birthday,
            }
        );

#        _add_history(
#            who  => $user->{username},
#            what => 'add "', params->{first_name}, ' ', params->{last_name}, '" address',
#        );
    }

    # Get the current entry
    my $entry = schema->resultset('Address')->find( { id => params->{id} } );

    # Update the entry
    if ( params->{update} && params->{first_name} ) {
        $entry->first_name( params->{first_name} );
        $entry->last_name( params->{last_name} );
        $entry->street( params->{street} );
        $entry->city( params->{city} );
        $entry->state( params->{state} );
        $entry->zip( params->{zip} );
        $entry->phone( params->{phone} );
        $entry->phone2( params->{phone2} );
        $entry->email( params->{email} );
        $entry->notes( params->{notes} );
        $entry->birthday($birthday);
        $entry->update;

#        _add_history(
#            who  => $user->{username},
#            what => 'update "', params->{first_name}, ' ', params->{last_name}, '" address',
#        );
    }

    # Delete the entry
    if ( params->{delete} ) {
        $entry->delete;

#        _add_history(
#            who  => $user->{username},
#            what => 'delete ', params->{id}, ' address',
#        );
    }

    redirect '/addressbook';
    halt;
};

get '/calendar/:year/:month' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Collect the parameters
    my $year  = params->{year}  || $YEAR;
    my $month = params->{month} || $MONTH;

    # Get the current entry
    my $entry = schema->resultset('Calendar')->find( { id => params->{id} } );

    # Set the entry to display
    my $record;
    if ( !params->{update} && params->{id} ) {
        $record = {
            id        => $entry->id,
            title     => $entry->title,
            month     => $entry->month,
            day       => $entry->day,
            important => $entry->important,
            note      => $entry->note,
        };
    }

    # Collect all the entries for the given month
    my $records;
    my $events = schema->resultset('Calendar')->search( { month => $month } );
    while ( my $result = $events->next ) {
        $records->{ $result->id } =
            {
                title => $result->title,
                month => $result->month,
                day   => $result->day,
            };
    }

    # Instantiate a calendar object
    my $cal = HTML::CalendarMonthSimple->new(
        month => $month,
        year  => $year
    );
    $cal->border(1);

    # Add the month entries to the calendar
    for my $id ( keys %$records ) {
        if ( $cal->getcontent( $records->{$id}{day} ) ) {
            $cal->addcontent( $records->{$id}{day}, '<br/>' );
        }
        $cal->addcontent(
            $records->{$id}{day},
            qq|<b><a href="/calendar/$year/$month?id=$id">$records->{$id}{title}</a></b>|
        );
    }

    # Get the first day of the given month/year
    my $dt = DateTime->new(
        year      => $year,
        month     => $month,
        day       => 1,
        time_zone => $TZ,
    );

    # Redirect to the calendar page
    template 'calendar', {
        calendar   => $cal->as_HTML,
        year       => $year,
        month      => $month,
        prev_year  => $dt->clone->subtract( months => 1 )->year,
        next_year  => $dt->clone->add( months => 1 )->year,
        prev_month => $dt->clone->subtract( months => 1 )->month,
        next_month => $dt->clone->add( months => 1 )->month,
        edit       => $record,
        method     => params->{id} ? 'update' : 'add',
    };
};

post '/event' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current user
    my $user  = logged_in_user;

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Collect the parameters
    my $year  = params->{year}  || $YEAR;
    my $month = params->{month} || $MONTH;
    my $day   = params->{day};
    my $title = params->{title};
    my $impor = params->{important};
    my $note  = params->{note};

    $impor = $impor && $impor eq 'on' ? 1 : 0;

    # Add a new entry
    send_error( 'No title given', 400 ) if params->{add} && !$title;
    if ( params->{add} && $title && $month && $day ) {
        schema->resultset('Calendar')->create(
            {
                title 	  => $title,
                month     => $month,
                day       => $day,
                important => $impor,
                note      => $note,
            }
        );

#        _add_history(
#            who  => $user->{username},
#            what => 'add "', $title, '" event',
#        );
    }

    # Get the current entry
    my $entry = schema->resultset('Calendar')->find( { id => params->{id} } );

    # Update an existing entry
    if ( params->{update} && $title && $month && $day ) {
        $entry->title($title);
        $entry->month($month);
        $entry->day($day);
        $entry->important($impor);
        $entry->note($note);
        $entry->update;

#        _add_history(
#            who  => $user->{username},
#            what => 'update "', $title, '" event',
#        );
    }

    # Delete an entry
    if ( params->{delete} ) {
        $entry->delete;

#        _add_history(
#            who  => $user->{username},
#            what => 'delete "', $title, '" event',
#        );
    }

    redirect "/calendar/$year/$month";
    halt;
};

get '/album' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    my $users = schema->resultset('User')->search( { active => 1 } );
    my $records;
    while ( my $result = $users->next ) {
        my @files = File::Find::Rule->file()->in( $ALBUM . '/' . $result->username );
        @files = grep { !/\.txt$/ } @files;
        my @mtimes = map { { name => $_, mtime => (stat $_)[9] } } @files;
        @files = map { $_->{name} } sort { $a->{mtime} <=> $b->{mtime} } @mtimes;
        @files = map { s/^public\/(.*)$/$1/r } @files;

        $records->{ $result->username } = $files[0] || '404.jpg';
    }

    template 'album', {
        month => $MONTH,
        year  => $YEAR,
        users => $records,
    };
};

post '/upload' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;

    my $target = params->{target};

    my $file = request->upload('filename');

    # If there is an upload, copy it to the album with a unique timestamp
    if ( $file ) {
        my $dest = $target eq 'Family' ? 'Family' : $user->{username};
        my $name = $dest . '/' . time . '-' . $file->filename;
        $file->copy_to("$ALBUM/$name");

        # Add a post to the chat about this upload.
        if ( params->{notify} ) {
            my $text = sprintf
                '%s %s: Uploaded a new photo: <a href="album/%s"><img src="album/%s" height="10%" width="10%" style="vertical-align: middle;" /></a>',
                $user->{username},
                DateTime->now(),
                $name, $name;
            "$text\n" >> io($FILE);
        }

#        _add_history(
#            who  => $user->{username},
#            what => 'add ', $name, ' file',
#        );
    }

    # Return to the user page
    redirect "/album/$target";
    halt;
};

post '/delete' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;

    my $file = params->{file};
    $file =~ s/[^\w.-]//g;  # Remove everything but alpha-nums, periods and hyphens

    my $target = params->{target};
    $target =~ s/[^\w]//g;  # Remove all non alpha-nums

    $file = "$ALBUM/$target/$file";

    if ( -e $file ) {
        unlink $file or die "Can't unlink $file: $!";

#        _add_history(
#            who  => $user->{username},
#            what => 'delete ', $file, ' file',
#        );
    }
    else {
        send_error( 'File does not exist', 400 );
    }

    # Return to the user page
    redirect "/album/$target";
    halt;
};

get '/album/:user' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;

    my $target = params->{user} // '';
    my $path = "$ALBUM/$target";

    # Collect the album files to display by most recent
    opendir my $dh, $path or die "Can't open $path: $!";
    my @files = reverse grep { !/^\./ && !/\.txt$/ }
        sort { ( stat "$path/$a" )[9] <=> ( stat "$path/$b" )[9] }
            readdir $dh;
    closedir $dh;

    my $captions;
    my $caption_file = "$path/$CAPTION";
    if ( -e $caption_file ) {
        open my $fh, '<', $caption_file
            or die "Can't read $caption_file: $!";
        while ( my $line = readline($fh) ) {
            chomp $line;
            my ( $filename, $caption ) = split /\t/, $line, 2;
            $captions->{$filename} = $caption;
        }
        close $fh
            or die "Can't close $caption_file: $!";
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    # Redirect to the album page
    template 'album-user', {
        files    => \@files,
        captions => $captions,
        target   => $target,
        user     => $user->{username},
        month    => $MONTH,
        year     => $YEAR,
    };
};

post '/caption' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $file         = params->{file};
    my $caption      = params->{caption};
    my $target       = params->{target};
    my $caption_file = "$ALBUM/$target/$CAPTION";

    if ( -e $caption_file ) {
        my $captions;

        open my $fh, '<', $caption_file
            or die "Can't read $caption_file: $!";
        while ( my $line = readline($fh) ) {
            chomp $line;
            my ( $filename, $caption ) = split /\t/, $line, 2;
            $captions->{$filename} = $caption;
        }
        close $fh
            or die "Can't close $caption_file: $!";

        $captions->{$file} = $caption;

        open $fh, '>', $caption_file
            or die "Can't write $caption_file: $!";
        for my $key ( keys %$captions ) {
            print $fh "$key\t$captions->{$key}\n";
        }
        close $fh
            or die "Can't close $caption_file: $!";
    }

    # Return to the user page
    redirect "/album/$target";
    halt;
};

sub _trim {
    my ($string) = @_;
    $string =~ s/^\s*//;
    $string =~ s/\s*$//;
    $string =~ s/\s+/ /g;
    return $string;
}

post '/tree' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $name   = _trim( params->{name} );
    my $parent = _trim( params->{parent} );
    my $date   = _trim( params->{date} );
    my $spouse = _trim( params->{spouse} );

    # Create a new entry
    if ( params->{add} && $name ) {
        if ($parent) {
            my $parent_obj = schema->resultset('Genealogy')->find( { name => $parent } );
            if ( !$parent_obj ) {
                schema->resultset('Genealogy')->create( { name => $parent } );
            }
        }

        schema->resultset('Genealogy')->create(
            {
                name   => $name,
                parent => $parent,
            }
        );
    }

    # Get the current entry
    my $entry = schema->resultset('Genealogy')->find( { id => params->{id} } );

    # Update the entry
    if ( $entry && params->{update} ) {
        if ($parent) {
            my $parent_obj = schema->resultset('Genealogy')->find( { name => $parent } );
            if ( !$parent_obj ) {
                schema->resultset('Genealogy')->create( { name => $parent } );
            }
        }

        $entry->name($name);
        $entry->parent($parent);
        $entry->date($date);
        $entry->spouse($spouse);
        $entry->update;
    }

    # Delete the entry
    if ( $entry && params->{delete} ) {
        $entry->delete;
    }

    redirect '/genealogy';
    halt;
};

get '/genealogy' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;

    # Get the current entry
    my $entry = schema->resultset('Genealogy')->find( { name => params->{name} } );

    # Set the record of the current entry, to display
    my $record;
    if ($entry) {
        $record = {
            id     => $entry->id,
            name   => $entry->name,
            parent => $entry->parent,
            date   => $entry->date,
            spouse => $entry->spouse,
        };
    }

    # Collect relations
    my $records;
    my $genealogy = schema->resultset('Genealogy')->search();
    while ( my $result = $genealogy->next ) {
        $records->{ $result->id } =
            {
                name   => $result->name,
                parent => $result->parent,
            };
    }
    my %relation;
    for my $id ( keys %$records ) {
        push @{ $relation{ $records->{$id}{parent} } }, $records->{$id}{name};
    }
    my $text = '';
    for my $root ( @{ $relation{''} } ) {
        $text = branch( $text, \%relation, $root, 0 );
    }

    template 'genealogy', {
        user      => $user->{username},
        relations => $text,
        edit      => $record,
        method    => $entry ? 'update' : 'add',
    };
};

sub branch {
    my ( $string, $relation, $branch, $level ) = @_;

    my $entry = schema->resultset('Genealogy')->find( { name => $branch } );

    my $padding = '&nbsp;' x 10;
    $string .= ( $padding x $level )
        . qq|<a href="/genealogy?name=$branch">$branch</a>|;
#        . $branch;
    $string .= ' ' . $entry->date
        if $entry->date;
    $string .= ' - ' . $entry->spouse
        if $entry->spouse;
    $string .= "<br/>\n";

    if ( exists $relation->{$branch} ) {
        for my $next_branch ( @{ $relation->{$branch} } ) {
            $string = branch( $string, $relation, $next_branch, $level + 1 );
        }
    }

    return $string;
}

get '/cookbook' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $record;
    my $records;
    my @sorted;

    if ( params->{id} ) {
        # Get the current entry
        my $entry = schema->resultset('Cookbook')->find( { id => params->{id} } );

        # Set the record of the current entry, to display
        $record = {
            id           => $entry->id,
            title        => $entry->title,
            user         => $entry->user,
            type         => $entry->type,
            note         => $entry->note,
            ingredients  => $entry->ingredients,
            instructions => $entry->instructions,
        };
    }
    else {
        my $where = params->{type} ? { type => params->{type} } : {};

        # Collect entries
        my $results = schema->resultset('Cookbook')->search( $where, { order_by => { -asc => 'title' } } );
        while ( my $result = $results->next ) {
            push @sorted, $result->id;
            $records->{ $result->id } =
                {
                    id    => $result->id,
                    title => $result->title,
                };
        }
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    template 'cookbook', {
        new    => params->{new},
        edit   => params->{edit},
        entry  => $record,
        data   => $records,
        sorted => \@sorted,
        month  => $MONTH,
        year   => $YEAR,
        method => params->{id} ? 'update' : 'add',
    };
};

post '/recipe' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;

    # Create a new entry
    if ( params->{add} && params->{title} ) {
        schema->resultset('Cookbook')->create(
            {
                title        => params->{title},
                user         => $user->{username},
                type         => params->{type},
                note         => params->{note},
                ingredients  => params->{ingredients},
                instructions => params->{instructions},
            }
        );

#        _add_history(
#            who  => $user->{username},
#            what => 'add ', params->{title}, ' recipe',
#        );
    }

    # Get the current entry
    my $entry = schema->resultset('Cookbook')->find( { id => params->{id} } );

    # Update the entry
    if ( params->{update} && params->{title} ) {
        $entry->title( params->{title} );
        $entry->type( params->{type} );
        $entry->note( params->{note} );
        $entry->ingredients( params->{ingredients} );
        $entry->instructions( params->{instructions} );
        $entry->update;

#        _add_history(
#            who  => $user->{username},
#            what => 'update ', params->{title}, ' recipe',
#        );
    }

    # Delete the entry
    if ( params->{delete} ) {
        $entry->delete;

#        _add_history(
#            who  => $user->{username},
#            what => 'delete ', params->{id}, ' recipe',
#        );
    }

    # Redirect appropriately
    if ( params->{update} || params->{add} ) {
        redirect '/cookbook?id=' . params->{id};
    }
    else {
        redirect '/cookbook';
    }
    halt;
};

sub _add_history {
    my (%args) = @_;

    schema->resultset('History')->create(
        {
            who         => $args{who},
            what        => $args{what},
            when        => DateTime->now(),
#            remote_addr => params->{remote_addr},
        }
    );
}

true;
