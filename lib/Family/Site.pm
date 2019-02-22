package Family::Site;

# ABSTRACT: Family::Site

our $VERSION = '0.23';

use Crypt::SaltedHash;
use Dancer qw( :syntax );
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC qw( schema resultset );
use Dancer::Plugin::FlashMessage;
use Date::Manip;
use DateTime;
use DateTime::Duration;
use DateTime::Format::DateParse;
use Email::Valid;
use Encoding::FixLatin qw( fix_latin );
use File::Find::Rule;
use File::Path qw( remove_tree );
use Geo::IP::PurePerl;
use HTML::CalendarMonthSimple;
use IO::All -utf8;
use Locale::US;
use Readonly;
use Text::Password::Pronounceable;
use Time::Ago;
use URL::Search qw( partition_urls );

Readonly my $FILE    => 'chat.txt';
Readonly my $CAPTION => 'caption.txt';
Readonly my $ALBUM   => 'public/album';
Readonly my $GEODAT  => $ENV{HOME} . '/geoip/GeoLiteCity.dat';
Readonly my $PWSIZE  => 6;
Readonly my $TZ      => config->{timezone};
Readonly my $ANGLE   => 'Angle brackets are not allowed. Please use the &lt; &gt; entities instead.';

sub is_blocked {
    my ($remote_address) = @_;
    return schema->resultset('Ban')->search( { ip => $remote_address } )->count ? 1 : 0;
}

get '/ban' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

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
        page   => 'ban',
        entry  => $record,
        data   => $records,
        sorted => \@sorted,
        method => params->{id} ? 'update' : 'add',
    };
};

post '/block' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

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
        my $new_entry = schema->resultset('Ban')->create(
            {
                ip        => $ip,
                last_seen => $now,
            }
        );

        _add_history(
            who  => $user->{username},
            what => "ban $ip, id: " . $new_entry->id,
            remote_addr => request->remote_address,
        );
    }

    # Get the current entry
    my $entry = schema->resultset('Ban')->find( { id => $id } );

    # Update the entry
    if ( $entry && params->{update} ) {
        $entry->ip($ip);
        $entry->last_seen($last_seen);
        $entry->update;

        _add_history(
            who  => $user->{username},
            what => "update ip ban id: $id",
            remote_addr => request->remote_address,
        );
    }

    # Delete the entry
    if ( $entry && params->{delete} ) {
        $entry->delete;

        _add_history(
            who  => $user->{username},
            what => "delete ip ban id: $id",
            remote_addr => request->remote_address,
        );
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
            $line = fix_latin($line);
            my ( $who, $when, $what ) = ( $line =~ /^(\w+) ([T \d:-]+): (.*)$/ );
            my $formatted = sprintf '<b>%s</b> <span class="smallstamp">%s:</span> %s',
                $who, $when, $what;
            push @content, '<p>' . $formatted . '</p>';
        }
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;

    # Collect the events for the current month
    my @cal;
    my $events = schema->resultset('Calendar')->search( { month => $MONTH }, { order_by => 'day' } );
    while ( my $result = $events->next ) {
        push @cal, {
            title => scalar fix_latin( $result->title ),
            month => $result->month,
            day   => $result->day,
            note  => scalar fix_latin( $result->note ),
        };
    }
    my @important;
    $events = schema->resultset('Calendar')->search(
        { important => 1, month => { '!=' => $MONTH } },
        { order_by => { -asc => [qw( month day )]  } }
    );
    while ( my $result = $events->next ) {
        push @important, {
            title => scalar fix_latin( $result->title ),
            month => $result->month,
            day   => $result->day,
            note  => scalar fix_latin( $result->note ),
        };
    }

    # Redirect to the main site template
    template 'index', {
        page      => 'family chat',
        user      => $user->{username},
        chat      => \@content,
        lines     => $lines,
        cal       => \@cal,
        important => \@important,
        month     => $MONTH,
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
    $text =~ s/(?:\r\n|\n){3,}/\n\n/g;

    # Append any user text to the chat file
    if ( defined $text && $text ne '' ) {
        $text = defang($text);

        my $now = DateTime->now( time_zone => $TZ )->ymd
            . ' ' . DateTime->now( time_zone => $TZ )->hms;
        my $html = '';
        for my $part ( partition_urls $text ) {
            my ( $type, $str ) = @$part;
            if ( $type eq 'URL' ) {
                $html .= qq|<a href="$str" target="_blank">$str</a>|;
            } else {
                $html .= $str;
            }
        }
        $text = $html;

        $text = sprintf '%s %s: %s',
            $user->{username},
            ( $stamp ? $now : '' ),
            $text;
        $text =~ s/\n/<br\/>/g;

        "$text\n" >> io($FILE);

        _add_history(
            who         => $user->{username},
            what        => 'chatted ' . length($text) . ' chars',
            remote_addr => request->remote_address,
        );
    }

    # Return to the main page
    redirect '/';
    halt;
};

get '/password' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );
    template 'password', {
        page => 'password',
        help => 0,
    };
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

        _add_history(
            who  => $user->{username},
            what => 'reset password',
            remote_addr => request->remote_address,
        );

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

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    # Collect the user records
    my $records;
    my $users = schema->resultset('User')->search( { last_login => { '!=' => undef } } );
    while ( my $result = $users->next ) {
        $records->{ $result->id } = {
            username    => scalar fix_latin( $result->username ),
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
            $last = fix_latin($line);
            last;
        }
    }

    my $MONTH = DateTime->now( time_zone => $TZ )->month;

    # Get the total number of calendar events and messages
    my $total = schema->resultset('Calendar')->count();
    my $total_msg = schema->resultset('Message')->count();

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
        page    => 'log',
        line    => $last,
        sorted  => \@sorted,
        files   => \@files,
        addr    => $addresses,
        recipes => $recipes,
        bans    => $bans,
        calnum  => $total,
        msgnum  => $total_msg,
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
            first_name => scalar fix_latin( $entry->first_name ),
            last_name  => scalar fix_latin( $entry->last_name ),
            street     => scalar fix_latin( $entry->street ),
            city       => scalar fix_latin( $entry->city ),
            state      => $entry->state,
            zip        => $entry->zip,
            phone      => $entry->phone,
            phone2     => $entry->phone2,
            email      => $entry->email,
            notes      => scalar fix_latin( $entry->notes ),
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
                first_name => scalar fix_latin( $result->first_name ),
                last_name  => scalar fix_latin( $result->last_name ),
                street     => scalar fix_latin( $result->street ),
                city       => scalar fix_latin( $result->city ),
                state      => $result->state,
                zip        => $result->zip,
                phone      => $result->phone,
                phone2     => $result->phone2,
                email      => $result->email,
                notes      => scalar fix_latin( $result->notes ),
                $result->birthday ? ( birthday => $result->birthday->ymd ) : (),
            };
    }

    my $us = Locale::US->new;
    my @code = $us->all_state_codes;

    # Redirect to the addressbook page
    template 'addressbook', {
        page   => 'addressbook',
        edit   => $record,
        data   => $records,
        sorted => \@sorted,
        method => params->{id} ? 'update' : 'add',
        states => \@code,
    };
};

post '/address' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $first_name = defang(params->{first_name});
    my $last_name = defang(params->{last_name});
    my $street = defang(params->{street});
    my $city = defang(params->{city});
    my $state = defang(params->{state});
    my $zip = defang(params->{zip});
    my $notes = defang(params->{notes});
    my $phone = defang(params->{phone});
    my $phone2 = defang(params->{phone2});
    my $email = defang(params->{email});

    # Get the current user
    my $user  = logged_in_user;

    # Create a new entry
    if ( params->{add} && $first_name ) {
        my $new_entry = schema->resultset('Address')->create(
            {
                first_name => $first_name,
                last_name  => $last_name,
                street     => $street,
                city       => $city,
                state      => $state,
                zip        => $zip,
                phone      => $phone,
                phone2     => $phone2,
                email      => $email,
                notes      => $notes,
            }
        );

        # Add a post to the chat about this entry.
        if ( params->{notify} ) {
            my $text = sprintf
                "%s %s: Added address for %s %s\n",
                $user->{username},
                DateTime->now( time_zone => $TZ ),
                $first_name, $last_name;
            $text >> io($FILE);
        }

        _add_history(
            who  => $user->{username},
            what => 'add address for ' . $first_name . ', id: ' . $new_entry->id,
            remote_addr => request->remote_address,
        );
    }

    # Get the current entry
    my $entry = schema->resultset('Address')->find( { id => params->{id} } );

    # Update the entry
    if ( params->{update} && $first_name ) {
        $entry->first_name($first_name);
        $entry->last_name($last_name);
        $entry->street($street);
        $entry->city($city);
        $entry->state($state);
        $entry->zip($zip);
        $entry->phone($phone);
        $entry->phone2($phone2);
        $entry->email($email);
        $entry->notes($notes);
        $entry->update;

        _add_history(
            who  => $user->{username},
            what => 'update address id: ' . params->{id},
            remote_addr => request->remote_address,
        );
    }

    # Delete the entry
    if ( params->{delete} ) {
        $entry->delete;

        _add_history(
            who  => $user->{username},
            what => 'delete address id: ' . params->{id},
            remote_addr => request->remote_address,
        );
    }

    redirect '/addressbook';
    halt;
};

get '/calendar' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    redirect '/calendar/' . $YEAR . '/' . $MONTH;
    halt;
};

get '/calendar/:year/:month' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Collect the parameters
    my $year  = params->{year};
    my $month = params->{month};

    # Get the current entry
    my $entry = schema->resultset('Calendar')->find( { id => params->{id} } );

    # Set the entry to display
    my $record;
    if ( !params->{update} && params->{id} ) {
        $record = {
            id        => $entry->id,
            title     => scalar fix_latin( $entry->title ),
            month     => $entry->month,
            day       => $entry->day,
            important => $entry->important,
            note      => scalar fix_latin( $entry->note ),
        };
    }

    # Collect all the entries for the given month
    my $records;
    my $events = schema->resultset('Calendar')->search( { month => $month } );
    while ( my $result = $events->next ) {
        $records->{ $result->id } =
            {
                title => scalar fix_latin( $result->title ),
                month => $result->month,
                day   => $result->day,
            };
    }

    # Collect all entries
    my $all_records;
    $events = schema->resultset('Calendar')->search( {}, { order_by => { -asc => [ 'month', 'day' ] } } );
    while ( my $result = $events->next ) {
        push @$all_records,
            {
                id    => $result->id,
                title => scalar fix_latin( $result->title ),
                month => $result->month,
                day   => $result->day,
            };
    }

    # Instantiate a calendar object
    my $cal = HTML::CalendarMonthSimple->new(
        month => $month,
        year  => $year
    );
    $cal->border(0);

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
        page       => 'calendar',
        calendar   => $cal->as_HTML,
        year       => $year,
        month      => $month,
        prev_year  => $dt->clone->subtract( months => 1 )->year,
        next_year  => $dt->clone->add( months => 1 )->year,
        prev_month => $dt->clone->subtract( months => 1 )->month,
        next_month => $dt->clone->add( months => 1 )->month,
        edit       => $record,
        entries    => $all_records,
        method     => params->{id} ? 'update' : 'add',
    };
};

post '/event' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    # Get the current user
    my $user  = logged_in_user;

    my $MONTH = DateTime->now( time_zone => $TZ )->month;
    my $YEAR  = DateTime->now( time_zone => $TZ )->year;

    send_error( 'Month range: 1-12. Day range: 1-31', 400 ) if params->{month} && params->{day}
        && !( params->{month} >= 1 && params->{month} <= 12
        && params->{day} >= 1 && params->{day} <= 31 );

    # Collect the parameters
    my $year  = params->{year}  || $YEAR;
    my $month = params->{month} || $MONTH;
    my $day   = params->{day};
    my $impor = params->{important};
    my $title = defang( params->{title} );
    my $note  = defang( params->{note} );

    $impor = $impor && $impor eq 'on' ? 1 : 0;

    # Add a new entry
    send_error( 'No title given', 400 ) if params->{add} && !$title;
    if ( params->{add} && $title && $month && $day ) {
        my $new_entry = schema->resultset('Calendar')->create(
            {
                title 	  => $title,
                month     => $month,
                day       => $day,
                important => $impor,
                note      => $note,
            }
        );

        # Add a post to the chat about this entry.
        if ( params->{notify} ) {
            my $text = sprintf
                "%s %s: Added %d/%d event: %s\n",
                $user->{username},
                DateTime->now( time_zone => $TZ ),
                $month, $day, $title;
            $text >> io($FILE);
        }

        _add_history(
            who  => $user->{username},
            what => 'add event: ' . $title . ', id: ' . $new_entry->id,
            remote_addr => request->remote_address,
        );
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

        _add_history(
            who  => $user->{username},
            what => 'update event id: ' . params->{id},
            remote_addr => request->remote_address,
        );
    }

    # Delete an entry
    if ( params->{delete} ) {
        $entry->delete;

        _add_history(
            who  => $user->{username},
            what => 'delete event id:' . params->{id},
            remote_addr => request->remote_address,
        );
    }

    redirect "/calendar/$year/$month";
    halt;
};

get '/album' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $users = schema->resultset('User')->search( { active => 1 } );
    my $records;
    while ( my $result = $users->next ) {
        next if $result->username eq 'Admin';

        my @files = File::Find::Rule->file()->in( $ALBUM . '/' . $result->username );
        @files = grep { !/\.txt$/ } @files;
        my @mtimes = map { { name => $_, mtime => (stat $_)[9] } } @files;
        @files = map { $_->{name} } sort { $a->{mtime} <=> $b->{mtime} } @mtimes;
        @files = map { s/^public\/(.*)$/$1/r } @files;

        $records->{ fix_latin( $result->username ) } = $files[0] || '/images/person.png';
    }

    template 'album', {
        page  => 'album',
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
            my $src = $name =~ /\.(gif|jpe?g|png)$/i ? "album/$name"
                : $name =~ /\.pdf$/i ? '/images/pdf.png'
                : $name =~ /\.mp3$/i ? '/images/audio.png'
                : $name =~ /\.mp4$/i ? '/images/video.png'
                : '/images/file.png';
            my $text = sprintf
                qq|%s %s: Uploaded: <a href="album/%s"><img src="%s" height="10%" width="10%" class="vmid" /></a>\n|,
                $user->{username},
                DateTime->now( time_zone => $TZ ),
                $name, $src;
            $text >> io($FILE);
        }

        _add_history(
            who  => $user->{username},
            what => 'add file: ' . $name,
            remote_addr => request->remote_address,
        );
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

        _add_history(
            who  => $user->{username},
            what => 'delete file: ' . $file,
            remote_addr => request->remote_address,
        );
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
    my @files;
    if ( -d $path ) {
        opendir my $dh, $path or die "Can't open $path: $!";
        @files = reverse grep { !/^\./ && !/\.txt$/ }
            sort { ( stat "$path/$a" )[9] <=> ( stat "$path/$b" )[9] }
                readdir $dh;
        closedir $dh;
    }

    my $captions;
    my $caption_file = "$path/$CAPTION";
    if ( -e $caption_file ) {
        open my $fh, '<', $caption_file
            or die "Can't read $caption_file: $!";
        while ( my $line = readline($fh) ) {
            chomp $line;
            my ( $filename, $caption ) = split /\t/, $line, 2;
            $captions->{$filename} = fix_latin($caption);
        }
        close $fh
            or die "Can't close $caption_file: $!";
    }

    # Redirect to the album page
    template 'album-user', {
        page     => $target,
        files    => \@files,
        captions => $captions,
        target   => $target,
        user     => $user->{username},
    };
};

post '/caption' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $file         = params->{file};
    my $caption      = defang( params->{caption} );
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
            title        => scalar fix_latin( $entry->title ),
            user         => $entry->user,
            type         => $entry->type,
            note         => scalar fix_latin( $entry->note ),
            ingredients  => scalar fix_latin( $entry->ingredients ),
            instructions => scalar fix_latin( $entry->instructions ),
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
                    title => scalar fix_latin( $result->title ),
                };
        }
    }

    template 'cookbook', {
        page   => 'cookbook',
        new    => params->{new},
        edit   => params->{edit},
        entry  => $record,
        data   => $records,
        sorted => \@sorted,
        method => params->{id} ? 'update' : 'add',
    };
};

post '/recipe' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $title = defang( params->{title} );
    my $note = defang( params->{note} );
    my $ingredients = defang( params->{ingredients} );
    my $instructions = defang( params->{instructions} );

    my $user = logged_in_user;

    # Create a new entry
    if ( params->{add} && params->{title} ) {
        my $new_entry = schema->resultset('Cookbook')->create(
            {
                title        => $title,
                user         => $user->{username},
                type         => params->{type},
                note         => $note,
                ingredients  => $ingredients,
                instructions => $instructions,
            }
        );

        # Add a post to the chat about this entry.
        if ( params->{notify} ) {
            my $text = sprintf
                "%s %s: Added recipe: %s\n",
                $user->{username},
                DateTime->now( time_zone => $TZ ),
                $title;
            $text >> io($FILE);
        }

        _add_history(
            who  => $user->{username},
            what => 'add recipe: ' . $title . ', id: ' . $new_entry->id,
            remote_addr => request->remote_address,
        );
    }

    # Get the current entry
    my $entry = schema->resultset('Cookbook')->find( { id => params->{id} } );

    # Update the entry
    if ( params->{update} && $title ) {
        $entry->title($title);
        $entry->type( params->{type} );
        $entry->note($note);
        $entry->ingredients($ingredients);
        $entry->instructions($instructions);
        $entry->update;

        _add_history(
            who  => $user->{username},
            what => 'update recipe id: ' . params->{id},
            remote_addr => request->remote_address,
        );
    }

    # Delete the entry
    if ( params->{delete} ) {
        $entry->delete;

        _add_history(
            who  => $user->{username},
            what => 'delete recipe id: ' . params->{id},
            remote_addr => request->remote_address,
        );
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
            remote_addr => $args{remote_addr},
        }
    );
}

get '/privacy' => sub {
    template 'privacy', {};
};

get '/help' => sub {
    template 'help', {};
};

get '/request' => sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    template 'request', {
        help => 0,
    };
};

post '/request_access' => sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    send_error( $ANGLE, 400 ) if params->{first_name} =~ /<|>/
        || params->{last_name} =~ /<|>/
        || params->{username} =~ /<|>/
        || params->{email} =~ /<|>/
    ;

    my $address = Email::Valid->address( params->{email} );

    send_error( 'Both first and last name are required', 400 ) unless params->{first_name} && params->{last_name};
    send_error( 'Invalid email', 400 ) unless $address;
    send_error( 'Month range: 1-12. Day range: 1-31', 400 ) if params->{month} && params->{day}
        && !( params->{month} >= 1 && params->{month} <= 12
        && params->{day} >= 1 && params->{day} <= 31 );

    schema->resultset('Message')->create(
        {
            first_name => params->{first_name},
            last_name  => params->{last_name},
            username   => params->{username},
            email      => params->{email},
            params->{month} ? ( month => params->{month} ) : (),
            params->{day} ? ( day => params->{day} ) : (),
        }
    );

    redirect '/';
    halt;
};

get '/users' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my @users;
    my $users = schema->resultset('User')->search( {}, { order_by => 'username' } );
    while ( my $result = $users->next ) {
        next if $result->username eq 'Admin';
        push @users, {
            id         => $result->id,
            username   => scalar fix_latin( $result->username ),
            active     => $result->active,
            admin      => $result->admin,
            last_login => $result->last_login,
        };
    }

    template 'users', {
        page  => 'users',
        users => \@users,
    };
};

post '/user_delete' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my $entry = schema->resultset('User')->search( { id => params->{id} } );
    $entry->delete;

    my $count = 0;
    my $path = "$ALBUM/" . params->{username};
    if ( params->{username} && -d $path ) {
        $count = remove_tree($path);
    }

    schema->resultset('History')->create(
        {
            who  => $user->{username},
            what => 'deleted id: ' . params->{id} . " ($count files removed)",
            remote_addr => request->remote_address,
        }
    );

    flash message => 'User ' . params->{username} . ' deleted';

    redirect '/users';
    halt;
};

post '/user_reset' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my $pass = Text::Password::Pronounceable->generate( $PWSIZE, $PWSIZE );

    my $entry = schema->resultset('User')->find( { id => params->{id} } );

    my $csh = Crypt::SaltedHash->new( algorithm => 'SHA-1' );
    $csh->add($pass);
    my $encrypted = $csh->generate;

    $entry->password($encrypted);
    $entry->active(0);
    $entry->update;

    schema->resultset('History')->create(
        {
            who  => $user->{username},
            what => 'reset password for id: ' . params->{id},
            remote_addr => request->remote_address,
        }
    );

    flash message => 'Password reset for user: ' . params->{username} . " to $pass";

    redirect '/users';
    halt;
};

get '/messages' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my @msg;
    my $messages = schema->resultset('Message')->search( {}, { order_by => 'stamp' } );
    while ( my $result = $messages->next ) {
        push @msg, {
            id         => $result->id,
            first_name => scalar fix_latin( $result->first_name ),
            last_name  => scalar fix_latin( $result->last_name ),
            username   => scalar fix_latin( $result->username ),
            email      => $result->email,
            month      => $result->month,
            day        => $result->day,
            message    => scalar fix_latin( $result->message ),
        };
    }

    template 'messages', {
        page     => 'messages',
        messages => \@msg,
    };
};

post '/grant_access' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my $pass = Text::Password::Pronounceable->generate( $PWSIZE, $PWSIZE );

    my $new_user = params->{username} || params->{first_name};

    my @entries = schema->resultset('User')->search( { username => $new_user } );
    send_error( 'Duplicate username', 400 ) if @entries;

    my $csh = Crypt::SaltedHash->new( algorithm => 'SHA-1' );
    $csh->add($pass);
    my $encrypted = $csh->generate;

    my $entry = schema->resultset('User')->create({ username => $new_user });
    $entry->password($encrypted);
    $entry->update;

    schema->resultset('Address')->create(
        {
            first_name => params->{first_name},
            last_name  => params->{last_name},
            email      => params->{email},
        }
    );

    if ( params->{month} && params->{day} ) {
        schema->resultset('Calendar')->create(
            {
                title => params->{first_name},
                month => params->{month},
                day   => params->{day},
            }
        );
    }

    my $path = "$ALBUM/$new_user";
    mkdir($path);
    open( my $fh, '>', "$path/caption.txt" ) if -d $path;

    my $msg = schema->resultset('Message')->search( { id => params->{id} } );
    $msg->delete;

    schema->resultset('History')->create(
        {
            who  => $user->{username},
            what => "new user: $new_user, id: " . $entry->id,
            remote_addr => request->remote_address,
        }
    );

    template 'email', {
        page     => 'email',
        name     => params->{first_name},
        username => $new_user,
        email    => params->{email},
        password => $pass,
        database => config->{plugins}{Database}{database},
        website  => 'http://dev.ology.net:8880/',
      };
};

post '/deny_access' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my $entry = schema->resultset('Message')->search( { id => params->{id} } );
    $entry->delete;

    redirect '/messages';
    halt;
};

get '/history' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    template 'history', {
        page => 'history',
    };
};

post '/history_search' => require_login sub {
    send_error( 'Not allowed', 403 ) if is_blocked( request->remote_address );

    my $user = logged_in_user;
    send_error( 'Not allowed', 403 ) unless is_admin( $user->{username} );

    my $when_start;
    my $when_end;
    if ( params->{when_start} || params->{when_end} ) {
        if ( params->{when_start} ) {
            $when_start = ParseDate( params->{when_start} );
            $when_start = join '-', UnixDate( $when_start, '%Y', '%m', '%d', '%T' );
        }
        else {
            $when_start = '1970-01-01';
        }
        if ( params->{when_end} ) {
            $when_end = ParseDate( params->{when_end} );
            $when_end = join '-', UnixDate( $when_end, '%Y', '%m', '%d', '%T' );
        }
        else {
            $when_end = '2032-12-31';
        }
    }

    my $where = {
        params->{who} ? ( who => params->{who} ) : (),
        params->{what} ? ( what => { LIKE => '%' . params->{what} . '%' } ) : (),
        $when_start ? ( when => { -between => [ $when_start, $when_end ] } ) : (),
        params->{remote_addr} ? ( remote_addr => params->{remote_addr} ) : (),
    };

    my $records;
    my $events = schema->resultset('History')->search( $where, { order_by => { -desc => 'when' } } );
    while ( my $result = $events->next ) {
        push @$records,
            {
                id          => $result->id,
                who         => scalar fix_latin( $result->who ),
                what        => scalar fix_latin( $result->what ),
                when        => $result->when,
                remote_addr => $result->remote_addr,
            };
    }

    template 'history', {
        page        => 'history',
        who         => params->{who},
        what        => params->{what},
        when_start  => $when_start,
        when_end    => $when_end,
        remote_addr => params->{remote_addr},
        entries     => $records,
        reset       => 0,
    };
};

sub defang {
    my ($text) = @_;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub is_admin {
    my ($username) = @_;
    my $entry = schema->resultset('User')->find( { username => $username } );
    return $entry->admin ? 1 : 0;
}

sub login_page_handler {
    my $login_fail_message = vars->{login_failed} ? 'LOGIN FAILED' : '';
    my $return_url = params->{return_url} || '';

    template 'login', {
        page       => 'login',
        error      => $login_fail_message,
        return_url => $return_url,
        help       => 0,
    };
}

true;
