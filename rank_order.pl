use strictures 1;
use RankBall;
use Statistics::RankOrder;
use Data::Dumper::Concise;

my $ro = Statistics::RankOrder->new();
my $rb = RankBall->new;
my %rd = $rb->rank_dispatcher; 
my %teams = map { $_ => 1 } $rb->all_teams;

# feeds are considered ranking sources: coaches, ap, rpi, pomerory, sagarin
foreach my $feed (keys %rd) {
    my $rankings = $rd{$feed}->();
    my @valid_teams = grep { $teams{$_} } keys %{$rankings}; 
    my @ranks = sort { $rankings->{$a} <=> $rankings->{$b} } @valid_teams;
    $ro->add_judge( [@ranks] );
}
print "Mean Rank: ";
my %mean_rank = $ro->mean_rank;
foreach my $team (sort { $mean_rank{$a} <=> $mean_rank{$b} }keys %mean_rank) {
    print "$team: $mean_rank{$team}\n";
}
my $team1 = 'Indiana';
my $team2 = 'Michigan State';
my %trimmed_mean_rank = $ro->trimmed_mean_rank(1);
print "$team1 Trimmed Mean Rank: ";
print "$trimmed_mean_rank{$team1}\n";
print "$team2 Trimmed Mean Rank: ";
print "$trimmed_mean_rank{$team2}\n";

my %median_rank = $ro->median_rank;
print "$team1 Median Rank: ";
print "$median_rank{$team1}\n";
print "$team2 Median Rank: ";
print "$median_rank{$team2}\n";

my %best_majority_rank = $ro->best_majority_rank;
print "$team1 Best Majority_Rank: ";
print "$best_majority_rank{$team1}\n";
print "$team2 Best Majority Rank: ";
print "$best_majority_rank{$team2}\n";