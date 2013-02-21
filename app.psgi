#!/usr/bin/env perl

package RankBaller;
use Web::Simple;
use RankBall;

has 'ranker' => (
  is => 'ro',
  default => sub { RankBall->new },
);

sub dispatch_request {
    my ($self, $env) = @_;

    sub (GET + ?sort~) {
        my ($self, $sort) = @_;
        [ 200, [ 'Content-type', 'text/html' ], [$self->ranker->report_rank_details_as_HTML(sort => $sort)] ];
      }, 
    sub () {
        [ 405, [ 'Content-type', 'text/plain' ], ['Method not allowed'] ];
      }
}

RankBaller->run_if_script;
