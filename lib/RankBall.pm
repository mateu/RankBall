package RankBall;
use Moo;
use WWW::Mechanize;
use HTML::TreeBuilder;
use HTML::TreeBuilder::Select;
use HTML::TableExtract;
use List::Util qw( reduce );

use Data::Dumper::Concise;

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

    my $url = 'http://kenpom.com';
    $self->mech->get($url);
    my $te = HTML::TableExtract->new(headers => [ 'Rank', 'Team', ],);
    $te->parse($self->mech->content);

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

    my $url = 'http://usatoday30.usatoday.com/sports/sagarin/bkt1213.htm';
    $self->mech->get($url);
    my $tree = HTML::TreeBuilder->new;
    $tree->parse_content($self->mech->content);
    my ($header, $data) = $tree->select("pre");
    my $text = $data->as_text;
    my @lines = split(/\r?\n/, $text);
    my %sagarin_rank_for;
    foreach my $line (@lines) {

        # Do we have a rank line
        if (my ($rank, $team) = $line =~ m/^\s*(\d+)\s*([\w\- ]*)\s*=/) {
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
sub teams_in_all {
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
    my $content = $self->$poll;
    if (not $content) {
        $self->mech->get($url_for{$poll});
        $content = $self->mech->content;
        $self->$poll($content);
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
    foreach my $team ($self->teams_in_all) {
        foreach my $ranking (keys %wanted_rankings) {
            $all{$team}->{$ranking} = $wanted_rankings{$ranking}->{$team}; 
        }
        $all{$team}->{sum} = reduce { $a + $b } values %{$all{$team}};
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
  $team =~ s/VCU\(Va. Commonwealth\)/Virginia Commonwealth/;
  return $team;
}

1
