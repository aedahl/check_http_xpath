#!/usr/bin/perl

#############################################################################
#                                                                           #
# This script was initially developed by Lonely Planet for internal use     #
# and has kindly been made available to the Open Source community for       #
# redistribution and further development under the terms of the             #
# GNU General Public License v3: http://www.gnu.org/licenses/gpl.html       #
#                                                                           #
#############################################################################
#                                                                           #
# This script is supplied 'as-is', in the hope that it will be useful, but  #
# neither Lonely Planet nor the authors make any warranties or guarantees   #
# as to its correct operation, including its intended function.             #
#                                                                           #
# Or in other words:                                                        #
#       Test it yourself, and make sure it works for YOU.                   #
#                                                                           #
#############################################################################
# Author: George Hansper       e-mail:  George.Hansper@lonelyplanet.com.au  #
#############################################################################

use strict;
use LWP;
use LWP::UserAgent;
use Getopt::Std;
use XML::XPath;
use Data::Dumper;

my %optarg;
my $getopt_result;

my $lwp_user_agent;
my $http_request;
my $http_response;
my $url;
my $body;
my @body;

my @message;
my @message_perf;
my %message_done_ndx;
my %message_done_result;
my %message_node_count_ok;
my %message_node_count_nok;
my $exit = 0;
my @exit = qw/OK: WARNING: CRITICAL:/;

my $rcs_id = '$Id: check_http_xpath.pl,v 1.1 2011/04/16 11:46:48 george Exp george $';
my $rcslog = '
	$Log: check_http_xpath.pl,v $
	Revision 1.1  2011/04/16 11:46:48  george
	Initial revision

	';

my $timeout = 10;			# Default timeout
my $host = 'localhost';		# default host header
my $host_ip = 'localhost';		# default IP
my $port = 80; 			# default port
my $user = 'nagios';		# default user
my $password = 'nagios';	# default password
#my $uri = '/manager/status?XML=true';			#tomcat status URI
my $uri = '/';
my $http = 'http';
my $regex_opts ="";
# Example xpaths
# /status/jvm/memory/@free 
# /status/connector[attribute::name="http-8080"]/threadInfo/@maxThreads
# /status/connector/threadInfo/@*
my $xpath;
my @xpath_checks;
my %invert_op = (
	'==' => '!=',
	'!=' => '=',
	'>'  => '<=',
	'>=' => '<',
	'<'  => '>=',
	'<=' => '>',
	'=~'   => '!~',
	'!~'   => '=~',
);

$getopt_result = getopts('hvSsiH:I:p:w:c:t:l:a:u:', \%optarg) ;

# Any invalid options?
if ( $getopt_result == 0 ) {
	HELP_MESSAGE();
	exit 1;
}
if ( $optarg{h} ) {
	HELP_MESSAGE();
	exit 0;
}
sub VERSION_MESSAGE() {
	print "$^X\n$rcs_id\n";
}

sub HELP_MESSAGE() {
	print <<EOF;
Usage:
	$0 [-v] [-H hostname] [-I ip_address] [-p port] [-S] [-t time_out] [-U user] [-P password] [-w /xpath[=value]...] [-c /xpath[=value]...]

	-H  ... Hostname and Host: header (default: $host)
	-I  ... IP address (default: none)
	-p  ... Port number (default: ${port})
	-S  ... Use SSL connection
	-v  ... verbose messages to STDERR for testing
	-s  ... summary mode - don't print node values, just report number of nodes found
	-t  ... Seconds before connection times out. (default: $timeout)
	-l  ... user for authentication (default: $user)
	-a  ... password for authentication (default: embedded in script)
	-u  ... uri path, (default: $uri)
	-w  ... warn on failure, space separated list of xpaths and optional values,
	        accepts operators ==  != > < <= >= =~ !~
	-c  ... critical on failure, space separated list, of xpaths and optional values,
	        accepts operators ==  != > < <= >= =~ !~
	-i  ... use case-insensitive regex's

	If the -w and -c expressions result in 'true' OK status is returned.
	If any expression is 'false' WARNING is generated if the expression was specified using -w,
	and CRITICAL is generated of the expression was specified using -c.

Notes:
	When using the operators '==' and '!=", values may be strings or numbers.
	Quoting is permitted eg "Are we there yet" or 'Are we there yet'
	Some characters are dissallowed in value strings: = ~ < > /

	The -I parameter connects to a alternate hostname/IP, using the Host header from the -H parameter

	Most HTML is not valid XML for the XML::XPath library that this plugin relies on, unfortunately.
	Carefully written HTML may give usable results
	
	In summary mode, if there is a CRITICAL or WARNING, only those nodes which are
	evaluating 'false' are listed in the output
	In regular mode, all matching nodes and values are listed, and those evaluating to 'false'
	have the reason (eg >=7) shown in brackets after the value.
	
	In summary mode, the performance information contains each XPATH, and the total number of matching nodes found,
	regardless of the result of the comparision
	In regular mode, the performance information contains each node as /xpath=value
	regardless of the result of the comparision

Example 1:
	To check if tomcat status page shows currentThreadsBusy >= 50 on port 8080
	$0 -H www.example.com -p 8080 -l nagios -a apples -u '/manager/status?XML=true' -c '/status/connector[attribute::name="http-8080"]/threadInfo/\@currentThreadsBusy<50'

Example 2:
	To check if tomcat status page shows currentThreadsBusy >= 20 on any port
	This checks as many matching XML nodes as it finds, and reports on each of them, or generates 'false' if no matching node is found
	$0 -H www.example.com -p 8080 -l nagios -a apples -u '/manager/status?XML=true' -w '/status/connector/threadInfo/\@currentThreadsBusy<20' -c '/status/connector/threadInfo/\@currentThreadsBusy<50'

Example 3:
	To check the latest alerts on the cert-us RSS feed (looking for regex /linux/i )
	$0 -H www.us-cert.gov -u /channels/techalerts.rdf -w '/rdf:RDF/item/title!~linux' -s -i

EOF
}

sub printv($) {
	if ( $optarg{v} ) {
		chomp( $_[-1] );
		print STDERR @_;
		print STDERR "\n";
	}
}

if ( defined($optarg{t}) ) {
	$timeout = $optarg{t};
}

# Is port number numeric?
if ( defined($optarg{p}) ) {
	$port = $optarg{p};
	if ( $port !~ /^[0-9][0-9]*$/ ) {
		print STDERR <<EOF;
		Port must be a decimal number, eg "-p 8080"
EOF
	exit 1;
	}
}

if ( defined($optarg{H}) ) {
	$host = $optarg{H};
	$host_ip = $host;
}

if ( defined($optarg{I}) ) {
	$host_ip = $optarg{I};
	if ( ! defined($optarg{H}) ) {
		$host = $host_ip;
	}
}

if ( defined($optarg{l}) ) {
	$user = $optarg{l};
}

if ( defined($optarg{a}) ) {
	$password = $optarg{a};
}

if ( defined($optarg{u}) ) {
	$uri = $optarg{u};
}

if ( defined($optarg{i}) ) {
	$regex_opts = 'i';
}

if ( defined($optarg{S}) ) {
	$http = 'https';
	if ( ! defined($optarg{p} ) ) {
		$port=443;
	}
}

sub parse_check_for($$) {
	my $arg = $_[0];
	my $exit_code = $_[1];
	my $xpath;
	my $op;
	my $expect;
	foreach ( split(m{\s+\/|^\/},$arg) ) {
		if ( /^$/ ) {
			next;
		}
		if ( /^(.*)([=><!]=|[><]|[!=]~)([^~=><]*)$/ ) {
			$xpath = '/'.$1;
			$op = $2;
			$expect = $3;
		} else {
			$xpath = '/'.$_;
			$op = "";
			$expect = "";
		}
		if ( $expect =~ /^\"(.*)\"$/ ) {
			$expect = $1;
		} elsif ( $expect =~ /^\'(.*)\'$/ ) {
			$expect = $1;
		}
		printv ("path='$xpath'   op='$op'   value='$expect'\n");
		push @xpath_checks, {xpath => $xpath, op=>$op, expect=>$expect, exit_code=>$exit_code};
	}
}

if ( defined($optarg{c}) ) {
	parse_check_for($optarg{c},2);
}

if ( defined($optarg{w}) ) {
	parse_check_for($optarg{w},1);
}

*LWP::UserAgent::get_basic_credentials = sub {
        return ( $user, $password );
};

sub node_to_xpath($$) {
	my $leaf_node = $_[0];
	my $xpath = $_[1];
	my $path = '' ;
	my $node;
	if ( $leaf_node->getNodeType() == 2 ) {
		# Attribute node, insert '/@name'
		$node = $leaf_node->getParentNode();
		$path = '/@' . $leaf_node->getLocalName();
	} else {
		$node = $leaf_node;
	}
	while ($node and $node->getParentNode()) {
		#my @attributes = $node->getAttributes();
		#if ( @attributes > 1 ) {
		#	$path = '['.($xpath->find('preceding-sibling::*[name()="'.$node->getName().'"]',$node)->size+1).']' . $path;
		#} elsif ( @attributes == 1 ) {
		#	$path = "[attribute::".$attributes[0]->toString().']'.$path;
		#}
		#$path = '['.$xpath->find('position()',$node)->value.']' . $path;
		$path = '['.($xpath->find('preceding-sibling::*[name()="'.$node->getName().'"]',$node)->size+1).']' . $path;
		$path = '/'.$node->getName() . $path;
		$node = $node->getParentNode();
	}
	return $path;
}

printv "Connecting to $host:${port}\n";

$lwp_user_agent = LWP::UserAgent->new;
$lwp_user_agent->timeout($timeout);
if ( $port == 80 || $port == 443 || $port eq "" ) {
	$lwp_user_agent->default_header('Host' => $host);
} else {
	$lwp_user_agent->default_header('Host' => "$host:$port");
}

$url = "$http://${host_ip}:${port}$uri";
$http_request = HTTP::Request->new(GET => $url);

printv "--------------- GET $url";
printv $lwp_user_agent->default_headers->as_string . $http_request->headers_as_string;

$http_response = $lwp_user_agent->request($http_request);
printv "---------------\n" . $http_response->protocol . " " . $http_response->status_line;
printv $http_response->headers_as_string;
printv "Content has " . length($http_response->content) . " bytes \n";

if ($http_response->is_success) {
	$body = $http_response->content;
	# <!DOCTYPE...> kills XML::XPath, strip it out
	$body =~ s/<!DOCTYPE ([^>]|\n)*>//i;
	# Make meta/link/img tags look like valid XML - ok it's a nasty hack
	# $body =~ s{(<(meta|link|img) ([^>]|\n)*[^/])>}{$1/>}gi;
	# printv("$body");
	my $xpath_check;
	foreach $xpath_check ( @xpath_checks ) {
		#print keys(%{$xpath_check}) , "\n";
		my $path = $xpath_check->{xpath};
		my $op = $xpath_check->{op};
		my $expect = $xpath_check->{expect};
		my $exit_code = $xpath_check->{exit_code};
		#print $xpath_check->{xpath} , "\n";
		my $xpath = XML::XPath->new( xml => $body );
		my $nodeset = $xpath->find($path);
		if ( $nodeset->get_nodelist == 0 ) {
			if ( ! defined($message_done_ndx{$path} ) ) {
				push @message, " $path not found";
				$message_done_ndx{$path} = $#message;
				$message_done_result{$path} = $exit_code;
				push @message_perf, "$path=not_found";
			}
			$exit |= $exit_code;
			next;
		}
		foreach my $node ($nodeset->get_nodelist) {
			my $value = $node->string_value();
			my $value_str = $value;
			my $path_uniq = "";
			if ( $value_str =~ /\s/ ) {
				if ( $value_str !~ /"/ ) {
					$value_str="\"$value_str\"";
				} elsif ( $value_str !~ /'/ ) {
					$value_str="'$value_str'";
				} else {
					# Backslash quote the quotes...
					$value_str =~ s/'/\'/g;
					$value_str="'$value_str'";
				}
			}
			my $result = 0;
			if ( $op eq '==' ) {
				if ( $expect =~ /^[-0-9.]+$/ ) {
					if ( ! ( $value == $expect ) ) {
						$result=$exit_code;
					}
				} else {
					if ( ! ( $value eq $expect ) ) {
						$result=$exit_code;
					}
				}
			} elsif ( $op eq '!=' ) {
				if ( $expect =~ /^[-0-9.]+$/ ) {
					if ( ! ( $value != $expect ) ) {
						$result=$exit_code;
					}
				} else {
					if ( ! ( $value ne $expect ) ) {
						$result=$exit_code;
					}
				}
			} elsif ( $op eq '=~' && defined($optarg{i}) ) {
				if ( ! ( $value =~ qr/$expect/i ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '=~' ) {
				if ( ! ( $value =~ $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '!~' && defined($optarg{i}) ) {
				if ( ! ( $value !~ qr/$expect/i ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '!~' ) {
				if ( ! ( $value !~ $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '>' ) {
				if ( ! ( $value > $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '>=' ) {
				if ( ! ( $value >= $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '<' ) {
				if ( ! ( $value < $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '<=' ) {
				if ( ! ( $value <= $expect ) ) {
					$result=$exit_code;
				}
			} elsif ( $op eq '' ) {
				#print $node->toString() , "\n";
				if ( $node->toString() eq "" ) {
					$result=$exit_code;
					$value = " not found";
				}
			} else {
				# Unreachable, unless there's a bug :-)
				print "$path\n";
				print "Unknown operator: '$op'\n";
				exit 2;
			}
			# Update the exit code...
			$exit |= $result;
			
			# Update the status and performance messages
			# Avoid duplicate messages for the same xpath, by using
			# 	%message_done_ndx flag
			# @message and @message_perf are arrays, so as to preserve the original order
			# %message_done_ndx gives the index into these arrays
			my $eq;
			if ( $value ne "" ) {
				$eq = '=';
			} else {
				$eq = '';
			}
			if ( $nodeset->get_nodelist == 1 || defined($optarg{s}) ) {
				# Unique node - just quote the original xpath
				# Or summary mode, where we just want to count nodes
				$path_uniq = $path;
			} else {
				# Disambiguise(?) the xpath
				$path_uniq = node_to_xpath($node,$xpath);
			}
			# The %message_done and %message_perf_done flags allow multiple checks to be done
			# on the same xpath without them appearing multiple times in the result message
			my $message_str ="";
			my $message_perf_str ="";
			if ( ! defined($optarg{s}) ) {
				# Regular output - give the value, and the reason (if not OK)
				$path =~ m{([^\][@/]*)$};
				$message_str = "$1$eq$value_str";
				if ( $result != 0 ) {
					$message_str .= "($invert_op{$op}$expect)";
				}
				$message_perf_str = "$eq$value_str";
			} else {
				# Summary output - operation and number of matches only
				# Note: warning/critical node will override OK message(s)
				$path =~ m{([^\][@/]*)$};
				$message_str = "$1";
				if ( $result == 0 ) {
					# Node was OK
					printv("count path ok: $path_uniq");
					$message_node_count_ok{$path_uniq} ++;
					$message_str = "$1$op$expect";
					$message_str .= " $message_node_count_ok{$path_uniq} found";
				} else {
					printv("count path nok: $path_uniq");
					$message_node_count_nok{$path_uniq} ++;
					$message_str .= "$invert_op{$op}$expect";
					$message_str .= " $message_node_count_nok{$path_uniq} found";
				}
				$message_perf_str = "=" . ($nodeset->get_nodelist);
			}
			if ( ! defined($message_done_ndx{$path_uniq} ) ) {
				# This is a new status message (for a new xpath)
				push @message, $message_str;
				push @message_perf, $message_perf_str;
				$message_done_ndx{$path_uniq} = $#message;
				$message_done_result{$path_uniq} = $result;
			} elsif ( $result >= $message_done_result{$path_uniq}) {
				# Allow a message to override an earlier message of lower/equal priority ($exit_code)
				# Especially in summary mode
				$message[$message_done_ndx{$path_uniq}] = $message_str;
				$message_done_result{$path_uniq} = $result;
				# Update the performance message, too
				$message_perf[$message_done_ndx{$path_uniq}] = $message_perf_str;
			} elsif ( defined($optarg{s}) ) {
				# Always update the performance message in summary mode
				$message_perf[$message_done_ndx{$path_uniq}] = $message_perf_str;
			}
			if ( $optarg{v} ) {
				printv ("FOUND: " .
				   " XPATH: " .
				   node_to_xpath($node,$xpath) .
				   " NODE: " .
				   $node->toString() .
				   "\tvalue: " .
				   $node->string_value()
				   );
			}
			#print $xpath->getNodeText($node) , "\n";
			#print $node->getName() , "\n";
			#print $node->getParentNode()->getParentNode()->getName() , "\n";
			#print "Test: " , $node->getData() , "\n";
			#print Dumper($node);

		}
	}
} else {
	print "CRITICAL: $url " . $http_response->protocol . " " . $http_response->status_line ."\n";
	exit 2;
}

if ( $exit == 3 ) {
	$exit = 2;
}

# Prune out OK messages if there is a warning or critical - necessary to avoid confusion about what's going wrong and why
if ( $exit >=1 && defined($optarg{s})) {
	foreach my $path ( keys(%message_done_ndx) ) {
		if( $message_done_result{$path} == 0 ) {
			$message[$message_done_ndx{$path}] = "";
		}
	}
}

print "$exit[$exit] ". join(" ",@message). "|". join(" ",@message_perf) . "\n";
exit $exit;
