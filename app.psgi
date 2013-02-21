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
        $sort ||= 'sum';
        [ 200, [ 'Content-type', 'text/html' ], [$self->ranker->wrapped_HTML(sort => $sort)] ];
      }, 
    sub () {
        [ 405, [ 'Content-type', 'text/plain' ], ['Method not allowed'] ];
      }
}

RankBaller->run_if_script;
