use Test::More tests => 2;
use strict;
use warnings;

# the order is important
use Family::Site;
use Dancer::Test;

route_exists [GET => '/login'], 'a route handler is defined for /login';
response_content_like [GET => '/login'], qr/Login Required/, 'content looks good for /login';
