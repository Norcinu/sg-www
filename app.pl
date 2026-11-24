#!/usr/bin/env perl
use Mojolicious::Lite -signatures;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json);
use Time::Piece;
use Time::Seconds qw(ONE_DAY);

my $config = plugin 'Config' => {file => path(__FILE__)->sibling('app.conf')};
app->secrets($config->{secrets});
app->sessions->secure(1) if app->mode eq 'production';

my $STATE_FILE     = path(__FILE__)->sibling('countdown_state.json');
my $BASE_DAYS      = 21; # 3 weeks
my $EXTEND_DAYS    = 7;  # 1 week per extension
my $MAX_EXTENSIONS = 3;

sub today_midnight {
    my $now = localtime;
    return Time::Piece->strptime($now->ymd, '%Y-%m-%d');
}

sub load_state {
    if (-e $STATE_FILE) {
        return decode_json($STATE_FILE->slurp);
    }

    my $state = {
        start_date => today_midnight()->ymd,
        extensions => 0,
        completed  => 0,
    };
    save_state($state);
    return $state;
}

sub save_state ($state) {
    $STATE_FILE->spew(encode_json($state));
}

get '/' => sub ($c) {
    my $state = load_state();
    my $start = Time::Piece->strptime($state->{start_date}, '%Y-%m-%d');
    my $today = today_midnight();

    my $days_passed = int(($today - $start) / ONE_DAY);
    $days_passed = 0 if $days_passed < 0;

    my $total_target_days = $BASE_DAYS + ($state->{extensions} * $EXTEND_DAYS);
    my $days_remaining    = $total_target_days - $days_passed;
    $days_remaining       = 0 if $days_remaining < 0;

    my $is_due       = ($days_passed >= $total_target_days);
    my $can_extend   = ($state->{extensions} < $MAX_EXTENSIONS);
    my $hard_stopped = ($is_due && !$can_extend && !$state->{completed});

    $c->stash(
        start_date        => $start->ymd,
        current_date      => $today->ymd,
        days_passed       => $days_passed,
        days_remaining    => $days_remaining,
        total_target_days => $total_target_days,
        extensions_used   => $state->{extensions},
        max_extensions    => $MAX_EXTENSIONS,
        completed         => $state->{completed},
        is_due            => $is_due,
        can_extend        => $can_extend,
        hard_stopped      => $hard_stopped,
    );

    $c->render(template => 'index');
};

# Validate CSRF token for all state-changing POST routes
under sub ($c) {
    my $v = $c->validation;
    return 1 unless $v->csrf_protect->has_error('csrf_token');

    $c->render(text => 'Bad CSRF token!', status => 403);
    return undef;
};

post '/complete' => sub ($c) {
    my $state = load_state();
    $state->{completed} = 1;
    save_state($state);
    $c->redirect_to('/');
};

post '/extend' => sub ($c) {
    my $state = load_state();
    if (!$state->{completed} && $state->{extensions} < $MAX_EXTENSIONS) {
        $state->{extensions}++;
        save_state($state);
    }
    $c->redirect_to('/');
};

post '/reset' => sub ($c) {
    unlink $STATE_FILE if -e $STATE_FILE;
    $c->redirect_to('/');
};

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>3-Week Countdown</title>
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 540px;
      margin: 3rem auto;
      padding: 0 1rem;
      line-height: 1.5;
      color: #1f2328;
    }
    .card {
      border: 1px solid #d0d7de;
      border-radius: 8px;
      padding: 1.5rem;
      background: #f6f8fa;
    }
    .stats {
      list-style: none;
      padding: 0;
      margin: 1rem 0;
    }
    .stats li {
      padding: 0.4rem 0;
      border-bottom: 1px solid #e5e8ec;
      display: flex;
      justify-content: space-between;
    }
    .actions {
      display: flex;
      gap: 0.75rem;
      margin-top: 1.25rem;
    }
    button {
      padding: 0.55rem 1.1rem;
      border-radius: 6px;
      border: 1px solid #1f2328;
      font-size: 0.95rem;
      cursor: pointer;
    }
    .btn-complete { background: #1a7f37; color: #fff; border-color: #1a7f37; }
    .btn-extend   { background: #0969da; color: #fff; border-color: #0969da; }
    .btn-reset    { background: #fff; color: #57606a; border-color: #d0d7de; margin-top: 1.5rem; }
    .banner {
      padding: 0.75rem 1rem;
      border-radius: 6px;
      font-weight: 600;
      margin-top: 1rem;
    }
    .banner-done { background: #dafbe1; color: #116329; }
    .banner-stop { background: #ffebe9; color: #82071e; }
  </style>
</head>
<body>
  <div class="card">
    <h2>Countdown Tracker</h2>
    <ul class="stats">
      <li><span>Start Date</span> <strong><%= $start_date %></strong></li>
      <li><span>Current Date</span> <strong><%= $current_date %></strong></li>
      <li><span>Days Passed</span> <strong><%= $days_passed %> / <%= $total_target_days %></strong></li>
      <li><span>Days Remaining</span> <strong><%= $days_remaining %></strong></li>
      <li><span>Extensions Used</span> <strong><%= $extensions_used %> / <%= $max_extensions %></strong></li>
    </ul>

    % if ($completed) {
      <div class="banner banner-done">Countdown completed and stopped.</div>
    % } elsif ($hard_stopped) {
      <div class="banner banner-stop">Final extension reached (3 of 3). Countdown stopped.</div>
    % } elsif ($is_due) {
      <p><strong>Time is up!</strong> Mark as completed or extend by 1 week.</p>
      <div class="actions">
        <form method="post" action="/complete">
          %= csrf_field
          <button type="submit" class="btn-complete">Completed</button>
        </form>
        % if ($can_extend) {
          <form method="post" action="/extend">
            %= csrf_field
            <button type="submit" class="btn-extend">Extend (+1 Week)</button>
          </form>
        % }
      </div>
    % } else {
      <p>Countdown active — check back daily.</p>
    % }
  </div>

  <form method="post" action="/reset">
    %= csrf_field
    <button type="submit" class="btn-reset">Reset Countdown</button>
  </form>
</body>
</html>
