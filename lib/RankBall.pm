package RankBall;
use Moo;
use List::Util qw( reduce );
use Storable;
use Module::Runtime qw(use_module);

has cache => (
    is => 'ro',
    lazy => 1,
    default => sub { use_module('Cache::FileCache')->new },
);
has data_expiry => (
    is => 'lazy',
    builder => sub { 0.05 },
);
has 'sort' => (
    is => 'lazy',
    builder => sub { 'sum' },
);
has rank_order => (
    is => 'ro',
    lazy => 1,
    builder => '_build_rank_order',
    handles => [qw( 
        mean_rank 
        trimmed_mean_rank 
        median_rank 
        best_majority_rank
    )],
);
has table_extract => (
    is => 'ro',
    lazy => 1,
    default => sub { use_module('HTML::TableExtract')->new(headers => [ 'Rank', 'Team', ]) },
);
has tree_builder => (
    is => 'ro',
    lazy => 1,
    default => sub {
        use_module('HTML::TreeBuilder::Select');
        use_module('HTML::TreeBuilder')->new;
    },
);

has mech => (
    is      => 'ro',
    lazy    => 1,
    default => sub { use_module('HTTP::Tiny')->new },
);
has polls => (
    is => 'ro',
    default => sub {1},
);
has powers => (
    is => 'ro',
    default => sub {1},
);
has ap => (
    is => 'rw',
);
has coaches => (
    is => 'rw',
);
has rpi => (
    is => 'rw',
);
has report_header => (
    is => 'ro',
    lazy => 1,
    builder => '_build_report_header',
);

sub pomeroy_ranks {
    my ($self,) = @_;
    my $source = 'pomeroy';
    my $url = 'http://kenpom.com';
    my $data = $self->cache->get($source);
    if (not $data) {
        warn "Getting data for ${source}";
        my $response = $self->mech->get($url);
        die "Failed to get {$url}" unless $response->{success};
        $data = $self->extract_pomeroy_ranks_from($response->{content});
        $self->cache->set($source, $data);
    }
    return $data;
}

sub extract_pomeroy_ranks_from {
    my ($self,$content) = @_;

    my $te = $self->table_extract;
    $te->parse($content);
    my %pomeroy_rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            next if (not ($team and $rank));
            # trim whitespace
            $team =~ s/\s*$//;
            $team = $self->canonicalize_team($team);
            $pomeroy_rank_for{$team} = $rank;
        }
    }
    return \%pomeroy_rank_for;
}

sub sagarin_ranks {
    my ($self,) = @_;

    my $source = 'sagarin'; 
    my $url = 'http://usatoday30.usatoday.com/sports/sagarin/bkt1213.htm';
    my $data = $self->cache->get($source);
    if (not $data) {
        warn "Getting data for ${source}";
        my $response = $self->mech->get($url);
        die "Failed to get {$url}" unless $response->{success};
        $data = $self->extract_sagarin_ranks_from($response->{content});
        $self->cache->set($source, $data, );
    }
    return $data
}

sub extract_sagarin_ranks_from {
    my ($self, $content) = @_;
    my $tree = $self->tree_builder;
    $tree->parse_content($content);
    my ($header, $data) = $tree->select("pre");
    my $text = $data->as_text;
    my @lines = split(/\r?\n/, $text);
    my %sagarin_rank_for;
    foreach my $line (@lines) {

        # Do we have a rank line. Teams with spaces, dashes, periods, and parenthesis
        # For example, Miami-Florida and VCU(Va. Commonwealth)
        if (my ($rank, $team) = $line =~ m/^\s*(\d+)\s*([\w\- \(\)\.]*)\s*=/) {
            $team =~ s/\s*$//;
            $team = $self->canonicalize_team($team);
            $sagarin_rank_for{$team} = $rank;
        }
    }
    return \%sagarin_rank_for;
}

sub rankings {
    my ($self, ) = @_;
    my @rankings;
    if ($self->polls) {
        push @rankings, qw(ap coaches);
    }
    if ($self->powers) {
        push @rankings, qw(sagarin pomeroy rpi);
    }
    return sort @rankings;
}

# If a team is in both the AP and Coaches poll then it's in all of them.
# These are the teams to consider, TODO: Ideally it should depend on the list
# of ranking sources we are to consider.
sub all_teams {
    my ($self, ) = @_;
    my %rd = $self->rank_dispatcher;
    my $ap = $rd{ap}->();
    my $coaches = $rd{coaches}->();
    return grep { $coaches->{$_} } keys %{$ap};
}

sub rank_dispatcher {
    my ($self, ) = @_;
    return (
        sagarin => sub { $self->sagarin_ranks },
        pomeroy => sub { $self->pomeroy_ranks },
        rpi     => sub { $self->generic_ranks('rpi') },
        coaches => sub { $self->generic_ranks('coaches') },
        ap      => sub { $self->generic_ranks('ap') },
    );
}
sub stat_dispatcher {
    my ($self, ) = @_;
    return {
        mean_rank          => sub { +{$self->mean_rank} },
        trimmed_mean_rank  => sub { +{$self->trimmed_mean_rank(1)} },
        best_majority_rank => sub { +{$self->best_majority_rank} },
        median_rank        => sub { +{$self->median_rank} },
    };
}

sub generic_ranks {
    my ($self, $source) = @_;

    # Source better match up with one of these keys
    my %url_for = (
        'coaches' => 'http://www.usatoday.com/sports/ncaab/polls/coaches-poll',
        'ap'      => 'http://www.usatoday.com/sports/ncaab/polls/ap',
        'rpi'     => 'http://rivals.yahoo.com/ncaa/basketball/polls?poll=5',
    );
    my $data = $self->cache->get($source);
    if (not $data) {
        warn "Getting data for ${source}";
        my $response = $self->mech->get($url_for{$source});
        die "Failed to get {$url_for{$source}}" unless $response->{success};
        $data = $self->extract_ranks_from($response->{content}, $source);
        $self->cache->set($source, $data, );
    }
    return $data;
}

sub extract_ranks_from {
    my ($self, $content, $source) = @_;

    my $te = $self->table_extract;
    $te->parse($content);
    my %rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            # Top 25 collected at this marker
            if (not defined $rank) {
                next;
            }
            last if ($rank =~ m/Schools Dropped Out/);
            # remove &#160; 
            my $junk;
            ($junk, $team) = split(/\n/, $team) if ($source eq 'coaches' or $source eq 'ap');
            $team =~ s/\n//g;
            $team =~ s/\s*$//;
            $team =~ s/^\s*//;
            next if (not ($team or $rank));
            ($rank) = $rank =~ m/(\d+)/;
            $team = $self->canonicalize_team($team);
            $rank_for{$team} = $rank;
        }
    }
    return \%rank_for;

}

sub all_ranks {
    my ($self, ) = @_;

    my $cache_key = 'all_ranks';
    my $data = $self->cache->get($cache_key);
    if (not $data) {
        warn "Getting data for ${cache_key}";
        $data = $self->build_all_ranks;
        $self->cache->set($cache_key, $data, );
    }
    return $data;
}

sub build_all_ranks {
    my ($self, ) = @_;

    my %rd = $self->rank_dispatcher;
    my @rankings = $self->rankings;
    my %wanted_rankings;
    foreach my $ranking (@rankings) {
       $wanted_rankings{$ranking} = $rd{$ranking}->();
    }
    my %all;
    # Lets use the teams that are in both the Coaches and AP top 25 poll.
    foreach my $team ($self->all_teams) {
        foreach my $ranking (keys %wanted_rankings) {
            $all{$team}->{$ranking} = $wanted_rankings{$ranking}->{$team}; 
        }
        my @ranks = values %{$all{$team}};
        $all{$team}->{sum} = reduce { $a + $b } @ranks;
        my $sd = $self->stat_dispatcher;
        foreach my $stat ($self->rank_stats) {
            $all{$team}->{$stat} = $sd->{$stat}->()->{$team};
        }
    }
    return \%all;
}

sub rank_stats {
    my ($self, ) = @_;
    return sort keys %{$self->stat_dispatcher};
}

sub _build_report_header {
    my ($self, ) = @_;
    my @report_header = ('position','team');
    push @report_header, map { 
        my $stat = $_;
        my $pre = "<a href='?sort=${stat}'>"; 
        $stat =~ s/_rank//g; 
        $stat =~ s/_/<br>\n/; 
        $pre . $stat . '</a>'; 
    } 'sum', $self->rank_stats;
    push @report_header, map { 
        "<a href='?sort=${_}'>${_}</a>"; 
    } $self->rankings;
    return \@report_header;
}

sub report_body {
    my ($self, $sort) = @_;
    $sort ||= 'sum';
    my $data_file = "/tmp/report_body.${sort}.storable";
    unlink $data_file if (-e $data_file and (-M $data_file > $self->data_expiry));
    my $data = eval { retrieve $data_file };
    if (not $data) {
        warn "Getting data for ${data_file}";
        $data = $self->build_report_body($sort);
        store $data, $data_file;
    }
    return $data

}

sub build_report_body {
    my ($self, $sort) = @_;

    my $all = $self->all_ranks;
    my $position = 1;
    my @report_body;
    foreach my $team (sort {$all->{$a}->{$sort} <=> $all->{$b}->{$sort}} keys %{$all}) {
        my @team_ranks = ($position,$team);
        push @team_ranks, $all->{$team}->{sum};
        foreach my $metric ($self->rank_stats, $self->rankings) {
            push @team_ranks, $all->{$team}->{$metric};
        }
        push @report_body, [@team_ranks];
        $position++;
    }
    return \@report_body;

}

sub report_rank_details {
    my ($self, %options) = @_;
    my $format = $options{format}||'csv';
    my $header = join(',', @{$self->report_header});
    my @report = ($header);
    foreach my $team_data (@{$self->report_body($options{sort})}) {
        my $line = join(',', @{$team_data});
        push @report, $line;
    }
    foreach my $line (@report) {
        print $line, "\n";
    }
}

sub report_rank_details_as_HTML {
    my ($self, %options) = @_;
    my $output;
    $output = '<table align="center" style="font-size: 1.22em; border-collapse:collapse;">';
    $output .= '<tr><th colspan="2"></th>
    <th colspan="5" 
    style="border: 1px silver dotted;">Rank Stats</th>
    <th colspan="5"
    style="border: 1px silver dotted;">Sources</th></tr>';
    my $header = '<tr>
    <th valign="bottom" style="border: 1px silver dotted;">' 
    . join('</th><th valign="bottom" style="border: 1px silver dotted;">'
    , @{$self->report_header}) . '</th></tr>';
    $output .= $header;
    my @data = @{$self->report_body($options{sort})};
    foreach my $i (0..$#data) {
        my $team_data = $data[$i];
        my $background_color = ($i % 2) ? 'antiquewhite' : 'white';
        my @team_data = @{$team_data};
        my $line = "<tr style='background-color:${background_color}'>";
        foreach my $j (0..$#team_data) {
           my $text_align = 'center';
           # Team name is in the 2nd slot, and it has a distict text alignment
           $text_align = 'left' if ($j == 1);
           $line .= "<td style='text-align:${text_align};'>";
           $line .= $team_data[$j];
           $line .= '</td>';
        }
        $line .= '</tr>';
        $output .= $line;
    }
    $output .= '</table>';
    return $output;
}

sub full_HTML {
    my ($self, %options) = @_;
    my $sort = $options{'sort'} || $self->sort;
    my $sort_text = $sort;
    $sort_text =~ s/_/ /g;
    my $h = use_module('HTML::Tiny')->new;
    my $title = 'College Basketball Rankings';
    my $html_page  = $h->html([
        $h->head( $h->title($title) ),
        $h->body([
            $h->h1({ style => 'text-align:center;' }, $title ),
            $self->report_rank_details_as_HTML(sort => $sort),
            $h->div({ style => 'text-align:center;'}, 
              "Sorted by ". $h->span({style => 'color:darkgreen;'}, $sort_text)
            ),
        ]),
    ]);
    return $html_page;
}

sub report_ranks {
    my ($self, ) = @_;
    my %all = %{$self->all_ranks}; 
    my %sum = map { $_ => $all{$_}->{sum} } keys %all;
    my $position = 1;
    print "Position,Team,Rank Sum\n";
    foreach my $team (sort { $sum{$a} <=> $sum{$b} } keys %sum) {
        print "$position,$team,$sum{$team}\n";
        $position++;
    }
}

sub canonicalize_team {
  my ($self, $team) = @_;
  die "No team" if not $team;
  $team =~ s/St\./State/;
  $team =~ s/Miami-Florida/Miami FL/;
  $team =~ s/Miami \(FL\)/Miami FL/;
  $team =~ s/^Miami$/Miami FL/;
  $team =~ s/VCU\(Va. Commonwealth\)/VCU/;
  $team =~ s/Va. Commonwealth/VCU/;
  $team =~ s/Virginia Commonwealth/VCU/;
  return $team;
}

sub _build_rank_order {
    my ($self, ) = @_;
    my %rd = $self->rank_dispatcher; 
    my %teams = map { $_ => 1 } $self->all_teams;
    my $rank_order = use_module('Statistics::RankOrder')->new;
    # Feeds are considered ranking sources: coaches, ap, rpi, pomerory, sagarin
    foreach my $feed (keys %rd) {
        my $rankings = $rd{$feed}->();
        my @valid_teams = grep { $teams{$_} } keys %{$rankings}; 
        my @ranks = sort { $rankings->{$a} <=> $rankings->{$b} } @valid_teams;
        $rank_order->add_judge( [@ranks] );
    }
    return $rank_order;
}

sub report_on {
    my ($self, $what, $trim) = @_;
    # Only trimmed_mean_ranks uses the $trim value
    my %report = $self->$what($trim);
    my @words = map { ucfirst($_) } split(/_/, $what);
    my $stat = join(' ', @words);
    print "Team,${stat}\n";
    foreach my $team (sort { $report{$a} <=> $report{$b} } keys %report) {
        print "$team,$report{$team}\n";
    }
}

sub compare_two_teams {
    my ($self, $team1, $team2) = @_;

    $team1 ||= 'Indiana';
    $team2 ||= 'Michigan State';

    print "Stat,$team1,$team2\n";

    my %mean_rank = $self->mean_rank;
    print "Mean Rank,";
    print "$mean_rank{$team1},";
    print "$mean_rank{$team2}\n";

    my %trimmed_mean_rank = $self->trimmed_mean_rank;
    print "Trimmed Mean Rank,";
    print "$trimmed_mean_rank{$team1},";
    print "$trimmed_mean_rank{$team2}\n";

    my %median_rank = $self->median_rank;
    print "Median Rank,";
    print "$median_rank{$team1},";
    print "$median_rank{$team2}\n";

    my %best_majority_rank = $self->best_majority_rank;
    print "Majority_Rank,";
    print "$best_majority_rank{$team1},";
    print "$best_majority_rank{$team2}\n";
}

1
