use strictures 1;
use RankBall;
use Data::Dumper::Concise;

my $ranker = RankBall->new;
$ranker->report_on('trimmed_mean_rank', 1);
$ranker->compare_two_teams('Indiana', 'Michigan State');

