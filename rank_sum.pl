use RankBall;
use Getopt::Long;
use List::Util qw( reduce );

my $polls  = 1;
my $powers = 1;
my $result = GetOptions(
    "polls=i"  => \$polls,
    "powers=i" => \$powers,
);

my $ranker = RankBall->new(
    polls  => $polls,
    powers => $powers,
);
$ranker->report_ranks;

