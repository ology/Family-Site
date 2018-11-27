use Test::More tests => 3;
use strict;
use warnings;

# the order is important
use Family::Site;
use Dancer::Test;

route_exists [GET => '/request'], 'a route handler is defined for /request';
response_status_is ['GET' => '/request'], 200, 'response status is 200 for /request';
response_content_like [GET => '/request'], qr/Request Access/, 'content looks good for /request';
