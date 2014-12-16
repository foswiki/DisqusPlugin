# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# DisqusPlugin is Copyright (C) 2013-2014 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::DisqusPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Meta ();
use Digest::MD5 ();

our $VERSION = '2.00';
our $RELEASE = '2.00';
our $SHORTDESCRIPTION = 'Disqus-based commenting system';
our $NO_PREFS_IN_TOPIC = 1;
our $doneDisqusInit = 0;
our $doneDisqusCount = 0;
our $doneDisqusEmbed = 0;

use constant TRACE => 0; # toggle me

sub initPlugin {

  Foswiki::Func::registerTagHandler('DISQUS', \&DISQUS);
  Foswiki::Func::registerTagHandler('DISQUS_COUNT', \&DISQUS_COUNT);
  Foswiki::Meta::registerMETA("DISQUS", # or do we standardize on PAGE_ID
    require => ['name'], 
    allow => ['description', 'date']
  ); 

  $doneDisqusInit = 0;
  $doneDisqusCount = 0;
  $doneDisqusEmbed = 0;

  return 1;
}

sub writeDebug {
  print STDERR "DisqusPlugin - $_[0]\n" if TRACE;
}

sub beforeSaveHandler {
  my ($text, $topic, $web, $meta) = @_;

  writeDebug("called beforeSaveHandler($web, $topic)");

  if ($text =~ /%DISQUS({.*?})?%/ || Foswiki::Func::getPreferencesFlag("DISPLAYCOMMENTS")) {
    my $disqusData = $meta->get("DISQUS");
    unless (defined $disqusData) {
      writeDebug("adding META::DISQUS");

      # normalize web name
      $web =~ s/\//./g;

      # store a page id stable between topic renames
      $meta->putKeyed("DISQUS", {
        name => Digest::MD5::md5_hex("$web.$topic"),
        date => time(),
      });
    }
  }
}

sub requireDisqusInit {
  return if $doneDisqusInit;
  $doneDisqusInit = 1;

  my $code = <<"HERE";
<script type="text/javascript">var disqus_shortname = "$Foswiki::cfg{DisqusPlugin}{ForumName}";</script>
HERE

  Foswiki::Func::addToZone("script", "DISQUS::INIT", $code, "JQUERYPLUGIN");
}

sub requireDisqusCount {
  return if $doneDisqusCount;
  $doneDisqusCount = 1;

  requireDisqusInit();

  my $code = <<'HERE';
<script type="text/javascript">
jQuery(function($) {
  window.DISQUSWIDGETS = undefined;
  $.getScript('//' + disqus_shortname + '.disqus.com/count.js');
});
</script>
HERE

  Foswiki::Func::addToZone("script", "DISQUS::COUNT", $code, "DISQUS::INIT");
}

sub requireDisqusEmbed {
  return if $doneDisqusEmbed;
  $doneDisqusEmbed = 1;

  requireDisqusInit();

  my $code = <<'HERE';
<script type="text/javascript">
jQuery(function($) {
  if (typeof(window.DISQUS) === 'undefined') {
    $.getScript('//' + disqus_shortname + '.disqus.com/embed.js');
  }
});
</script>
HERE

  Foswiki::Func::addToZone("script", "DISQUS::EMBED", $code, "DISQUS::INIT");
}

sub DISQUS_COUNT {
  my ($session, $params, $topic, $web) = @_;

  writeDebug("called DISQUS_COUNT{$web, $topic}");

  my $webTopic = $params->{_DEFAULT} || $params->{topic} || $topic;
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $webTopic);

  my ($meta) = Foswiki::Func::readTopic($web, $topic);
  my $disqusData = $meta->get("DISQUS");
  return "" unless defined $disqusData;

  my $id = $disqusData->{name};
  return "" unless defined $id;

  requireDisqusCount();

  my $format = $params->{format} || '<a href="$url" class="disqus-comment-count" data-disqus-identifier="$id"></a>';
  my $viewUrl = Foswiki::Func::getScriptUrl($web, $topic, "view", '#' => 'disqus_thread');
  $format =~ s/\$url/$viewUrl/g;
  $format =~ s/\$id/$id/g;

  return $format;
}

sub DISQUS {
  my ($session, $params, $topic, $web) = @_;

  writeDebug("called DISQUS($web, $topic)");

  my $webTopic = $params->{_DEFAUT} || $params->{topic} || $topic;
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $webTopic);

  my ($meta) = Foswiki::Func::readTopic($web, $topic);
  my $disqusData = $meta->get("DISQUS");
  return "" unless defined $disqusData;

  my $id = $disqusData->{name};
  return "" unless defined $id;

  my @vars = ();
  push @vars, "disqus_identifier = '$id'";

  my $title = $params->{title};
  push @vars, "disqus_title = '$title'" if defined $title;

  my $url = $params->{url};
  push @vars, "disqus_url = '$url'" if defined $url;

  my $category = $params->{category};
  push @vars, "disqus_category_id = '$category'" if defined $category;

  my $vars = join(",\n   ", @vars);

  requireDisqusEmbed();

  return <<"HERE";
<div id="disqus_thread"></div>
<script type="text/javascript">
var $vars;
if (typeof(window.DISQUS) !== 'undefined') {
  DISQUS.reset({
    reload: true,
    config: function () {
      this.page.identifier = disqus_identifier;
    }
  });
}
</script>
HERE
}

1;
