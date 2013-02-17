use RankBall;
use Getopt::Long;
use List::Util qw( reduce );

my $polls  = 1;
my $powers = 1;
my $result = GetOptions(
    "polls=i"  => \$polls,
    "powers=i" => \$powers,
);

my $ranker = RankBall->new;
use DDP;
my %s   = $ranker->get_sagarin_ranks;
my %p   = $ranker->get_pomeroy_ranks;
my %c   = $ranker->get_ranks('coaches');
my %ap  = $ranker->get_ranks('ap');
my %rpi = $ranker->get_ranks('rpi');

#p %rpi;
my @teams_in_all = grep { $c{$_} and $ap{$_} } keys %s;

#warn "Teams in All: ", p @teams_in_all;
my %sum;
foreach my $team (@teams_in_all) {

    # Only teams that exist in all polls.
    my @sources;
    if ($polls) {
        push @sources, \%c, \%ap;
    }
    if ($powers) {
        push @sources, \%s, \%p, \%rpi;
    }
    my @ranks = map { $_->{$team} } @sources;
    $sum{$team} = reduce { $a + $b } @ranks;

    #  $p{$team} + $s{$team} + $c{$team} + $ap{$team} + $rpi{$team};
}
my $position = 1;
print "Position,Team,Rank Sum\n";
foreach my $team (sort { $sum{$a} <=> $sum{$b} } keys %sum) {

    #  next if $position > 20;
    print "$position,$team,$sum{$team}\n";
    $position++;
}

sub debug_team {
    my ($team,) = @_;
    $team ||= 'Indiana';
    print "Team: $team\n";
    print "IU pom rank: $p{$team}\n";
    print "IU sag rank: $s{$team}\n";
    print "IU coach rank: $c{$team}\n";
    print "IU AP rank: $ap{$team}\n";
    print "IU RPI rank: $rpi{$team}\n";
}

sub is_in_all_teams {
    my $team = shift;
    return (  defined $s{$team}
          and defined $p{$team}
          and defined $c{$team}
          and defined $ap{$team}
          and defined $rpi{$team});
}
