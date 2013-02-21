use RankBall;
use Getopt::Long;
use HTML::Tiny;

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
 
my $h = HTML::Tiny->new;
my $title = 'College Basketball Rankings';
print $h->html(
  [
    $h->head( $h->title($title) ),
    $h->body(
      [
        $h->h1( { style => 'text-align:center;' }, $title ),
        $ranker->report_rank_details_as_HTML,
      ]
    )
  ]
);

