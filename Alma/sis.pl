#!/usr/bin/perl

###################################################
#
# This script parses the CSV file received from IDM
# and converts it to the xml format required for Alma
# SIS sychronization.
# 
# 1 updated the expiry date for faculty group from 365 to 400 days to avoid the issue
#   with fixed due date
# 2 2019.12.18 only use student email address as primary contact email adress
# 3 2020.5.4 removing the line to give teaching and researh assistant faculty 
#   privileges 
# 4 2020.5.18 updated the expiry date for undergraduate group from 90 to 100 
#   days.
# 5 2020.5.21 add the line back to give teaching and research assistant faculty
#   priviledges 
# 6 2020.9.23 update CheckDualStatus function. There were some logic error for
#   determining user group. Update the email address to student email address 
#   if a patron has both staff and student email address.
#
###################################################

use strict;
use Encode;
use warnings;
use Data::Dumper;
use Text::CSV;
use Date::Calc qw(Add_Delta_Days check_date);
use IO::Compress::Zip qw(zip $ZipError);

my $this_script = $0;
my $xml_dir = "/home/exlibris/Alma/synchronize";
my $csv_dir = "/home/exlibris/Alma/sisftp";
my $log_dir = "/home/exlibris/Alma/logs";
my $mail_rcp ='fenlu@uta.edu';

# patron CSV file
my $DIR;
my $csv_file;
my $csv_file_name;

opendir DIR, $csv_dir or die "Cannot open $csv_dir: $!\n";
# Count the number of files in sisftp folder, if there is no file added, exit the program.
my $count=0;
while( $csv_file_name = readdir DIR){
	next if (($csv_file_name =~ /^\.$/) or ($csv_file_name =~ /^\.\.$/));
	$count++;
	if ($csv_file_name =~ /csv$/){
		$csv_file = "$csv_dir/$csv_file_name";
		last;
	}
}
print "Count: $count!\n";
closedir(DIR);

# File rootname
my $base_name = "sis";

# Session log
my $log_file = "$log_dir/$base_name.log.".`date +%Y%m%d`;
chomp($log_file);

#This is the output file to be used for "bad" records
my $bad_records = "$log_dir/$base_name.bad.".`date +%Y%m%d`;
chomp($bad_records);

#This is the output file for SIS sychronization
my $xml_file = "$xml_dir/$base_name.xml";

# Debug file
my $debug_file = "$log_dir/$base_name.debug.".`date +%Y%m%d`;
chomp($debug_file);

#############################################################
#
#  Open output files

#  Session log file
open (LOGFILE, ">$log_file")
	|| die "Cannot create/open log file: $!\n";
print LOGFILE $this_script . "\t" . `date` . "\n";

#  Bad record log
open (BADOUT, ">$bad_records")
         || die "Can't open $bad_records: $!.\n";
print BADOUT $this_script . "\t" . `date` . "\n";

#  Debug file
open (BUGOUT, ">$debug_file")
         || die "Can't open $debug_file: $!.\n";

# Output XML file
open (XMLFILE, ">$xml_file")
	|| die "Cannot create/open xml file: $!\n";

#  Catch interrupt signals ("^C") and close down the
#  open files before quitting the script.
$SIG{INT} = \&HandleSignalInt;

############################################################
#  Initialize counters
############################################################
my $recs_proc = 0;  # number of records processed 
my $recs_und  = 0;  # number of undergraduate students
my $recs_grad = 0;  # number of graduate students
my $recs_staff = 0; # number of staff employees
my $recs_fac = 0;   # number of records with faculty status
my $recs_ret = 0;   # number of retirees
my $recs_good = 0;  # number of good records
my $recs_bad = 0;   # number of bad records
my $recs_hon = 0;   # number of students in honor program 
my $total_recs = 0; # number of unique records
my $recs_dual = 0;  # number of records with dual status

if ( $count ==0){
        print LOGFILE "no csv file delivered!";
        &Finish(2);
}

&ReadCSVFile;
&WriteXMLFile;
&Finish(0);

############################################################
#  ReadCSVFile
############################################################

my @unique_records= ();

sub ReadCSVFile{
	open my $fh, "<", $csv_file or die "Cannot open $csv_file: $!";

  	my $csv = Text::CSV->new ({
      		binary    => 1, # Allow special character. Always set this
      		auto_diag => 1, # Report irregularities immediately
      		});
  	while (my $line = $csv->getline ($fh)) {
	
		my $patron_group = "";
		my $expire_days = "100";
	
		# If not the first line
		
		next if ($line->[0] =~ /^uta/);
		$recs_proc++;
		if ($recs_proc =~ /0000/){
			print LOGFILE "Processed ".$recs_proc." records!\n";
		}
                #print "$recs_proc"+" : ";
		#print "@$line\n";
		my ($utaEmplID, $utaStudentHonors, $utaPersonAffiliation, $givenName, $utaMiddleName, $surname, $utaStudentAcademicProgram, $utaHomeCity, $utaHomeCountry, $utaHomeState, $utaHomeStreet1, $utaHomeStreet2, $utaHomeZip, $mail, $utaEmployeeStatus) = @$line;

		#$utaEmplID = $line->[0];
		#$utaStudentHonors = $line->[1];
		#$utaPersonAffiliation = $line->[2];
		#$givenName = $line->[3];
		#$utaMiddleName = $line->[4];
		#$surname = $line->[5];
		#$utaStudentAcademicProgram = $line->[6];

		# Remove special characters
		$utaHomeCity =~ tr/\&/ /;
		$utaHomeStreet1 =~ tr/\&/ /;
		$utaHomeStreet2 =~ tr/\&/ /;

		#$utaHomeCountry = $line->[8];
		#$utaHomeState = $line->[9];
		#$utaHomeZip = $line->[12];
		#$mail = $line->[13];
		#$utaEmployeeStatus = $line->[14];
		if ( $mail !~ /@/ ){
			&BadRecord ( $utaEmplID, "no email address");
		}
		if ( $mail =~ /edu,/ ){
			#&BadRecord ( $utaEmplID, "two email address");
			my @twoEmails = split /,/, $mail;
			$mail = $twoEmails[0]; 
			&BadRecord ( $utaEmplID, $mail);
		}
		# the records without email address won't be imported
		next if ( $mail !~ /@/ );
					
			if (length($utaHomeZip) == 9) {
			        $utaHomeZip = substr($utaHomeZip,0,5) . "-" . substr($utaHomeZip,5,4);
    			}
			
			# looking for characters outside the ASCII range
			if ($surname =~ /[\x80-\xff]/) {
        			print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $surname . "\n";
        			$surname =  encode("iso-8859-1",decode("utf8", $surname));
			}
			if ($utaMiddleName =~ /[\x80-\xff]/) {
                                print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $utaMiddleName . "\n";
                                $utaMiddleName =  encode("iso-8859-1",decode("utf8", $utaMiddleName));
                        }

			if ($givenName =~ /[\x80-\xff]/) {
				print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $givenName . "\n";
				$givenName =  encode("iso-8859-1",decode("utf8", $givenName));
			}

			if ($utaHomeStreet1 =~ /[\x80-\xff]/) {
                                print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $utaHomeStreet1 . "\n";
                                $utaHomeStreet1 =  encode("iso-8859-1",decode("utf8", $utaHomeStreet1));
                        }
			if ($utaHomeStreet2 =~ /[\x80-\xff]/) {
                                print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $utaHomeStreet2 . "\n";
                                $utaHomeStreet2 =  encode("iso-8859-1",decode("utf8", $utaHomeStreet2));
                        }
			if ($utaHomeCity =~ /[\x80-\xff]/) {
                                print BUGOUT "non-ASCII" . "\t" . $utaEmplID . "\t" . $utaHomeCity . "\n";
                                $utaHomeCity =  encode("iso-8859-1",decode("utf8", $utaHomeCity));
                        }


			if ($utaEmployeeStatus =~ /Retired/i){
				$recs_ret++;
				$patron_group = "retfac";
			}

			if ($utaPersonAffiliation =~ /Student/i && 
			    $utaStudentHonors =~ /true/i &&
			    $utaStudentAcademicProgram =~ /undergrad/i){
				$recs_hon++;
				$patron_group = "honors";
				$expire_days = "180";
			} elsif ($utaPersonAffiliation eq "Student") {
				if ($utaStudentAcademicProgram =~ /masters/i ||
				    $utaStudentAcademicProgram =~ /doctoral/i ||
				    $utaStudentAcademicProgram =~ /certificates/i ||
				    $utaStudentAcademicProgram =~ /special/i){
					$patron_group = "grad";
	                                $expire_days = "180";
					$recs_grad++;
				} elsif ($utaStudentAcademicProgram =~ /undergrad/i ||
					 $utaStudentAcademicProgram =~ /baccelaureate/i ){
					$patron_group = "und";
					$recs_und++;
				} else {
					&BadRecord ($utaEmplID, "Unknown student classification");
				}
			} elsif ($utaPersonAffiliation =~ /faculty/i ||
				 $utaPersonAffiliation =~ /admin/i ||
				 $utaPersonAffiliation =~ /librarian/i ||
				 $utaPersonAffiliation =~ /assistant/i) {
					$recs_fac++;
					$patron_group = "fac";
					$expire_days = "400";
			} elsif ($utaPersonAffiliation =~ /employee/i && $utaEmployeeStatus =~ /active/i){
				$patron_group = "staff";
				$recs_staff++;
			} 
		#print LOGFILE $utaEmplID.", ".$patron_group."\n";	
		my $status_date = &TodaysDatePlus(0);
		my $expire_date = &TodaysDatePlus($expire_days);
		my $purge_days  = $expire_days + 180;
		my $purge_date  = &TodaysDatePlus($purge_days);	
		my $mail2 = "";
		my $curr_ref = [$utaEmplID,  $patron_group, $givenName, $utaMiddleName, $surname, $mail, $mail2, $utaHomeCity, $utaHomeCountry, $utaHomeState, $utaHomeStreet1, $utaHomeStreet2, $utaHomeZip, $status_date, $expire_date, $purge_date];
		#print "@$curr_ref\n";
		if ($patron_group ne ""){
			&CheckDualStatus ($curr_ref);
		
		}
	}
	close $fh;
}

############################################################
#  CheckDualStatus
############################################################

sub CheckDualStatus {
	my ($curr_ref) = @_;
	my $size=0;
	my $i=0;

	push @unique_records, $curr_ref;
	$size = $#unique_records+1;
	#print scalar @unique_records;
	#print "$size\n";
	while ($i < $size-1){
		
		if ($curr_ref->[0] eq $unique_records[$i]->[0]){
			$recs_dual++;
			#print LOGFILE $unique_records[$i]->[1]."|".$curr_ref->[1]."      ";
			if ($unique_records[$i]->[1] eq "und" &&($curr_ref->[1] eq "grad" || $curr_ref->[1] eq "honors" || $curr_ref->[1] eq "fac")) {
				$unique_records[$i]->[1] = $curr_ref->[1];
				$unique_records[$i]->[14] = $curr_ref->[14];
				$unique_records[$i]->[15] = $curr_ref->[15];
			} elsif ($unique_records[$i]->[1] eq "grad" && $curr_ref->[1] eq "fac"){
				$unique_records[$i]->[1] = $curr_ref->[1];
				$unique_records[$i]->[14] = $curr_ref->[14];
                                $unique_records[$i]->[15] = $curr_ref->[15];
			} elsif ($unique_records[$i]->[1] eq "staff" && $curr_ref->[1] ne "retfac"){
				 $unique_records[$i]->[1] = $curr_ref->[1];
				 $unique_records[$i]->[14] = $curr_ref->[14];
                                 $unique_records[$i]->[15] = $curr_ref->[15];
			} elsif ($unique_records[$i]->[1] eq "honors" && ($curr_ref->[1] eq "fac"||$curr_ref->[1] eq "grad")){
                                $unique_records[$i]->[1] = $curr_ref->[1];
                                $unique_records[$i]->[14] = $curr_ref->[14];
                                $unique_records[$i]->[15] = $curr_ref->[15];
                        }

		# if the second record's email address is different, it will be added as the second identifer.		
			if ($curr_ref->[5] ne $unique_records[$i]->[5]){
				# adding a second email address
				$unique_records[$i]->[6] = $curr_ref->[5];
				#print LOGFILE $curr_ref->[0].":".$unique_records[$i]->[0]."|".$curr_ref->[5].":".$unique_records[$i]->[5]."\n";
			}
			pop @unique_records;
			last;
		}
		$i++;
	}
	
	#print "@$curr_ref\n";	
}

sub WriteXMLFile{
	print LOGFILE "Start to write to ". $xml_file. "\n";
	print XMLFILE "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n";
	print XMLFILE "<users>\n";
	#print scalar @unique_records;

	while (my $element = shift(@unique_records)){
		#print "@$element\n";
		print XMLFILE "<user>\n";
                print XMLFILE "<record_type>PUBLIC</record_type>\n";
		print XMLFILE "<primary_id>".$element->[0]."</primary_id>\n";
                print XMLFILE "<first_name>".$element->[2]."</first_name>\n";
                print XMLFILE "<last_name>".$element->[4]."</last_name>\n";
                print XMLFILE "<middle_name>".$element->[3]."</middle_name>\n";
                print XMLFILE "<user_group>".$element->[1]."</user_group>\n";
		print XMLFILE "<expiry_date>".$element->[14]."</expiry_date>\n";
		print XMLFILE "<purge_date>".$element->[15]."</purge_date>\n";
		print XMLFILE "<account_type desc=\"External\">EXTERNAL</account_type>\n";
		print XMLFILE "<external_id>SIS</external_id><password></password><force_password_change></force_password_change>\n";
		print XMLFILE "<status_date>".$element->[13]."</status_date>\n";
                print XMLFILE "<status desc=\"Active\">ACTIVE</status>\n";
                print XMLFILE "<contact_info>\n";
		print XMLFILE "<addresses><address preferred=\"true\" segment_type=\"External\">\n";
		if ($element->[10] eq ''){
			print XMLFILE "<line1>None </line1>\n";
		}
		else {
                print XMLFILE "<line1>".$element->[10]."</line1>\n";
		}
                print XMLFILE "<city>".$element->[7]."</city>\n";
                print XMLFILE "<state_province>".$element->[9]."</state_province>\n";
		print XMLFILE "<postal_code>".$element->[12]."</postal_code>\n";
                print XMLFILE "<country>".$element->[8]."</country>\n";
                print XMLFILE "<start_date>".$element->[13]."</start_date>";
                print XMLFILE "<end_date>".$element->[14]."</end_date>";
		print XMLFILE "<address_types><address_type desc=\"Home\">home</address_type></address_types>";
                print XMLFILE "</address></addresses>\n";

#Only student email address is used for primary contact email address
		my $email;
		if ($element->[6] eq ''){
			$email= $element->[5];
		} elsif ($element->[5] =~ /mavs.uta.edu/i){
			$email = $element->[5]; 
		} else {
                        $email = $element->[6];
                }
		print XMLFILE "<emails><email preferred=\"true\" segment_type=\"External\"><email_address>".$email."</email_address><email_types><email_type desc=\"Personal\">personal</email_type><email_type desc=\"School\">school</email_type><email_type desc=\"Work\">work</email_type></email_types></email></emails>\n";
                print XMLFILE "</contact_info>\n";
                print XMLFILE "<user_identifiers>\n";
                print XMLFILE "<user_identifier><id_type desc=\"Barcode\">BARCODE</id_type>\n";
                print XMLFILE "<value>".$element->[5]."</value>\n";
		print XMLFILE "<status>ACTIVE</status>\n";
                print XMLFILE "</user_identifier>\n";
		if ($element->[6] ne ""){
                	print XMLFILE "<user_identifier><id_type desc=\"Barcode\">BARCODE</id_type>\n";
                	print XMLFILE "<value>".$element->[6]."</value>\n";
                	print XMLFILE "<status>ACTIVE</status>\n";
                	print XMLFILE "</user_identifier>\n";

		}
                print XMLFILE "</user_identifiers>\n";
                print XMLFILE "</user>\n";
	
	}
			
	print XMLFILE "</users>\n";	
        print LOGFILE "Finished writing $xml_file ! \n"; 
}


############################################################
#  BadRecord
############################################################

sub BadRecord {
    my ($uta_id, $reason) = @_;
    $recs_bad++;
    print BADOUT $uta_id . "\t" . $reason . "\n";
}

############################################################
#  TodaysDatePlus
############################################################
#
#  Takes an integer as arguement and adds that many
#  days to today's date.
 
sub TodaysDatePlus {
    my ($date_offset) = @_;
    #use Date::Calc qw(Add_Delta_Days check_date);
    my ($sec, $min, $hour, $mday, $mon, $year,
        $wday, $yday, $isdat) = localtime(time);
        $mon         += 1;
        $year        += 1900;
    ($year, $mon, $mday)
        = Add_Delta_Days($year, $mon, $mday, $date_offset);
        $mon           = sprintf("%02d", $mon);
        $mday          = sprintf("%02d", $mday);
    if (check_date($year, $mon, $mday)) {
        my $future_date = $year . "-" . $mon . "-"  . $mday.'+06:00';
        return($future_date);
    } else {
        return('');
    }
}

sub HandleSignalInt {
    &Finish(9);
}

sub Finish {
    my ($exit_status) = @_;
    if (! ($exit_status =~ /\d/) ) {
        $exit_status = 7;
    }
    if ($exit_status !~ /^2$/){
    print LOGFILE "Records processed:   " . sprintf("%6d",$recs_proc) . "\n";
    print LOGFILE "Number of bad recs:  " . sprintf("%6d",$recs_bad)  . "\n";
    print LOGFILE "Number of undergrads:" . sprintf("%6d",$recs_und)  . "\n";
    print LOGFILE "Number of grads:     " . sprintf("%6d",$recs_grad) . "\n";
    print LOGFILE "Number of students in honor program:	" . sprintf("%6d", $recs_hon) . "\n";
    print LOGFILE "Number of staff: " . sprintf("%6d",$recs_staff) . "\n";
    print LOGFILE "Number of faculty:   " . sprintf("%6d",$recs_fac)  . "\n";
    print LOGFILE "Number of retirees:  " . sprintf("%6d",$recs_ret)  . "\n";
    print LOGFILE "Number of stud/empl: " . sprintf("%6d",$recs_dual) . "\n";
    }

    close (XMLFILE);
    close (BADOUT);
    close (BUGOUT); 
     if ($exit_status !~ /^2$/){
    my $zip_file = "/home/exlibris/Alma/synchronize/sis.zip";
    zip $xml_file => $zip_file or print LOGFILE "zip failed :$ ZipError\n";
    my $csv_file_done = "/home/exlibris/Alma/synchronize/original_data/$csv_file_name";
    rename($csv_file, $csv_file_done) or print LOGFILE "ERROR: couldn't move $csv_file to $csv_file_done \n";
    }
    
    print LOGFILE "DONE \n";
    close (LOGFILE);
    #system qq(cat $log_file | /bin/mailx -s "Log: SIS synchronization" $mail_rcp);
    `/usr/sbin/sendmail $mail_rcp <$log_file`;
    exit($exit_status);
}

exit(0);
