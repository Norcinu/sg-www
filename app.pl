#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

get '/' => sub ($c) {
    $c->render(template => 'index');
};

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>sgleed.co.uk</title>
</head>
<body>
    <h1>sgleed.co.uk on Debian 13 LON1 (Mojolicious)</h1>
</body>
</html>
