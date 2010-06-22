#!/usr/bin/env perl

# usage:
# $> perl guardian_monitor.pl -c guardian.cfg

use strict;

use Getopt::Std;
use Config::Simple;
use HTML::Parser;
use LWP::Simple;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use URI;
use JSON::XS qw(encode_json decode_json);
use FileHandle;

{
    &main();
    exit;
}

sub main {

    my %opts = ();
    getopts('c:', \%opts);

    my $cfg = Config::Simple->new($opts{'c'});

    my $updates_json = $cfg->param('guardian.updates_path');
    my %updates = ();

    foreach my $url (fetch_blogs()){

        print "fetch updates for $url\n";

	$updates{ $url } = {
	    'updates' => parse_blog($url),
	};
    }

    my $updates_fh = FileHandle->new();
    binmode($updates_fh, ':utf8');

    if (! $updates_fh->open($updates_json, 'w')){
        warn $!;
        return 0;
    }

    $updates_fh->print(encode_json(\%updates));
    $updates_fh->close();

    print "wrote updates to $updates_json\n";
    return 1;
}

sub parse_blog(){
    my $url = shift;

    my $start = sub {
	my $parser = shift;
	my $tag = shift;
	my $attrs = shift;

	if (($tag eq 'div') && ($attrs->{'id'} eq 'article-wrapper')){
	    $parser->{'record'} = 1;
	    return;
	}

	if ((! $parser->{'record'}) || ($tag ne 'p')){
	    return;
	}

	if ($attrs->{'id'} =~ /^block-(\d+)$/){

	    my $id = $1;

	    if ($parser->{'block'}){

		my $idx = $parser->{'block'} - 1;

		my $blurb = $parser->{'buffer'};
		my $hex = md5_hex($blurb);

		$parser->{'blocks'}->[$idx] = [ $hex, $blurb ];
		$parser->{'buffer'} = '';
	    }

	    $parser->{'block'} = $id;
	}

    };

    my $end = sub {
	my $parser = shift;
	my $tag = shift;

	if (($parser->{'record'}) && ($tag eq 'div')){
	    $parser->{'record'} = 0;
	}
    };

    my $char = sub {
	my $parser = shift;
	my $data = shift;

	if (! $parser->{'record'}){
	    return;
	}

	$data =~ s/^\s+//;
	$data =~ s/\s+$//;

	if (! $data){
	    return;
	}

	if ($parser->{'buffer'}){
	    $data = ' ' . $data;
	}

        # No idea why this is coming through in a <p>
        # tag and not the <figcaption> that I see in 
        # the source...

        if ($data =~ /Photograph\:/){
            return;
        }

	$parser->{'buffer'} .= $data;
    };

    my $p = HTML::Parser->new('start_h' => [$start, 'self, tagname, attr'],
			      'end_h' => [ $end, 'self, tagname'],
			      'text_h' => [ $char, 'self, text' ],
	);

    $p->utf8_mode(1);

    $p->{'current_block'} = undef;
    $p->{'blocks'} = [];
    $p->{'buffer'} = undef;
    $p->{'record'} = 0;

    my $hex = md5_hex($url);
    my $tmp = "/tmp/$hex";

    # because calling plain old 'get()' resulted in
    # weird errors I didn't feel like debugging on
    # an airplane somewhere over the midwest during
    # the first US-UK game...

    if (! getstore($url, $tmp)){
	warn "failed to retrieve $url, $!";
	return [];
    }

    $p->parse_file($tmp);
    unlink($tmp);

    return $p->{'blocks'};
}

sub fetch_blogs {

    my @blogs = ();

    my($day, $month, $year)=(localtime)[3,4,5];
    my $today = sprintf("%04d-%02d-%02d", $year + 1900, $month + 1, $day);

    my %query = (
        "q" => "live",
        "tag" => "tone/minutebyminute",
        "section" => "football",
        "from-date" => $today,
        "to-date" => $today,
        "order-by" => "newest",
        "format" => "json",
        "show-tags" => "all",
        );

    my $endpoint = "http://content.guardianapis.com/search";
      
    my $uri = URI->new($endpoint);
    $uri->query_form(%query);

    my $json = get($uri);
    my $data = decode_json($json);

    foreach my $res (@{$data->{'response'}->{'results'}}){
        my $blog = $res->{'webUrl'};

        if ($blog eq "http://www.guardian.co.uk/football/2010/jun/21/world-cup-2010-live-blog"){
            next;
        }

        push @blogs, $blog;
    }

    return @blogs;
}
