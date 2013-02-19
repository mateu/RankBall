package RankBall;
use Moo;
use MooX::Types::MooseLike::Base qw( InstanceOf );
use Statistics::RankOrder;
use WWW::Mechanize;
use HTML::TreeBuilder;
use HTML::TreeBuilder::Select;
use HTML::TableExtract;
use List::Util qw( reduce );
use CHI;
use Data::Dumper::Concise;

has cache => (
    is => 'ro',
    lazy => 1,
    default => sub { CHI->new( driver => 'File', root_dir => '/tmp') },
);
has rank_order => (
    is => 'ro',
    isa => InstanceOf['Statistics::RankOrder'],
    lazy => 1,
    builder => '_build_rank_order',
    handles => [qw( 
        mean_rank 
        trimmed_mean_rank 
        median_rank 
        best_majority_rank
    )],
);
has mech => (
    is      => 'ro',
    lazy    => 1,
    default => sub { WWW::Mechanize->new },
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

sub pomeroy_ranks {
    my ($self,) = @_;

    my $source = 'pomeroy';
    my $url = 'http://kenpom.com';
    my $content = $self->cache->get($source);
    if (not $content) {
        warn "Getting content from ${source}";
        $self->mech->get($url);
        $content = $self->mech->content;
        $self->cache->set($source, $content, "1 hour");
    } 
    my $te = HTML::TableExtract->new(headers => [ 'Rank', 'Team', ],);
    $te->parse($content);

    my %pomeroy_rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            next if (not ($team or $rank));
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
    my $content = $self->cache->get($source);
    if (not $content) {
        warn "Getting content from ${source}";
        $self->mech->get($url);
        $content = $self->mech->content;
        $self->cache->set($source, $content, "1 hour");
    } 
    my $tree = HTML::TreeBuilder->new;
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

sub generic_ranks {
    my ($self, $poll) = @_;
    my %url_for = (
        'coaches' => 'http://www.usatoday.com/sports/ncaab/polls/coaches-poll',
        'ap'      => 'http://www.usatoday.com/sports/ncaab/polls/ap',
        'rpi'     => 'http://rivals.yahoo.com/ncaa/basketball/polls?poll=5',
    );
    my $content = $self->cache->get($poll);
    if (not $content) {
        warn "Getting content from ${poll}";
        $self->mech->get($url_for{$poll});
        $content = $self->mech->content;
        $self->cache->set($poll, $content, "1 hour");
    } 
    my $te = HTML::TableExtract->new(headers => [ 'Rank', 'Team', ],);
    $te->parse($content);

    my %rank_for;
    foreach my $table ($te->tables) {
        foreach my $row ($table->rows) {
            my ($rank, $team) = @{$row}[0..1];
            # Top 25 collected at this marker
            last if ($rank =~ m/Schools Dropped Out/);
            # remove &#160; 
            my $junk;
            ($junk, $team) = split(/\n/, $team) if ($poll eq 'coaches' or $poll eq 'ap');
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
    # Lets use the teams that are in both the Coaches and AP top 25 poll.
    my %rd = $self->rank_dispatcher;
    my @rankings = $self->rankings;
    my %wanted_rankings;
    foreach my $ranking (@rankings) {
       $wanted_rankings{$ranking} = $rd{$ranking}->();
    }
    my %all;
    foreach my $team ($self->all_teams) {
        foreach my $ranking (keys %wanted_rankings) {
            $all{$team}->{$ranking} = $wanted_rankings{$ranking}->{$team}; 
        }
        my @ranks = values %{$all{$team}};
        $all{$team}->{sum} = reduce { $a + $b } @ranks;
    }
    return \%all;
}

sub report_rank_details {
    my ($self, ) = @_;
    my $all = $self->all_ranks;
    my $position = 1;
    print "Position,Team,Rank Sum,";
    print join(',', $self->rankings), "\n";
    foreach my $team (sort {$all->{$a}->{sum} <=> $all->{$b}->{sum}} keys %{$all}) {
        print "$position,$team,";
        print $all->{$team}->{sum};
        foreach my $ranking ($self->rankings) {
            print ',', $all->{$team}->{$ranking};
        }
        print "\n";
        $position++;
    }
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
    my $rank_order = Statistics::RankOrder->new;
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
