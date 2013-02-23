package MyPackage;
use Web::Simple;
use Module::Runtime qw(use_module);

has 'ranker' => (
  is => 'lazy',
  builder => sub { use_module('RankBall')->new },
);

sub dispatch_request {
    sub (GET + ?sort~) {
        my $html_page = $_[0]->ranker->full_HTML(sort => $_[1]);
        [ 200, [ 'Content-type', 'text/html' ], [$html_page] ];
      }, 
}

__PACKAGE__->run_if_script;
