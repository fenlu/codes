#!/usr/bin/perl

##############################################
#
# BURSAR TRANSFER
# 2018 Fen Lu fenlu@uta.edu
# University of Texas at arlington
# Processese the bursar file generated and exported from Alma.
# The file is converted from xml format to csv format.
##############################################

use strict;
use warnings;
use XML::LibXML;

# Variables
my $this_script = $0;
my $bursar_xml_dir = "/home/exlibris/Alma/bursar";
my $bursar_csv_dir = "/home/exlibris/Alma/aisftp";
my $bursar_done_dir = "/home/exlibris/Alma/bursar_DONE";

# Bursar export xml file from Alma site
my $xml_file_name;
my $xml_file;
my $xml_file_done;

# Bursar csv file that needs to be imported by OIT
my $csv_file = "bursar.csv";

# Session log
my $log_file = "/home/exlibris/Alma/logs/bursar.log.".`date +%Y%m%d`;

open (LOGFILE, ">$log_file")
        ||die "Cannot open $log_file: $!\n";

print LOGFILE "Subject: Burar Transfer\n";
print LOGFILE $this_script . "\t" . `date` . "\n";

my $email_recipients = 'fenlu@uta.edu';

if (-e "/home/exlibris/Alma/aisftp/bursar.csv") {
	print LOGFILE "bursar.csv has not been processed!";
	close(LOGFILE);
	`/usr/sbin/sendmail $email_recipients <$log_file`;
	exit 0;
}
else {
	open (CSVFILE, ">$bursar_csv_dir/$csv_file")
        	||die "Cannot open $bursar_csv_dir/$csv_file: $!\n";
}

&CheckXMLDirectory;


####################################################
# CheckXMLDirectory
####################################################

sub CheckXMLDirectory{
	# Check to make sure bursar xml file has been ftp'd from Alma site

	my $DIR;
	opendir DIR, $bursar_xml_dir or die "Cannot open $bursar_xml_dir: $!\n";
	while (  $xml_file_name = readdir DIR ){
		if ($xml_file_name =~ /xml$/){
			print LOGFILE "*********Start to process: ".$xml_file_name."********\n\n";
			&ReadXMLFile;
		}	
	}
	close(CSVFILE);
	close(LOGFILE);
	`/usr/sbin/sendmail $email_recipients <$log_file`;

}

####################################################
# ReadXMLFile
####################################################

sub ReadXMLFile{

	#Variables;
	my $bursar_trans_id;
	my $patronName;
	my $EmplID;

	$xml_file = "$bursar_xml_dir/$xml_file_name";
	$xml_file_done = "$bursar_done_dir/$xml_file_name.DONE";
	#print LOGFILE "process xml file: ".$xml_file."\n\n";
	open (XMLFILE, "<$xml_file")
	         ||die "Cannot open $xml_file: $!\n";
	
	my $dom = XML::LibXML->load_xml(location=>$xml_file);
	
	$bursar_trans_id = $dom->findvalue('.//xb:exportNumber');
	
	foreach my $userExportedList ($dom->findnodes('//xb:userExportedList/xb:userExportedFineFeesList')){
		$EmplID = $userExportedList->findvalue('./xb:user/xb:value');
 		$patronName = $userExportedList->findvalue('./xb:patronName');
		foreach my $finefeeList ($userExportedList->findnodes('./xb:finefeeList/xb:userFineFee')){
			my $itemTitle = $finefeeList->findvalue('./xb:itemTitle');
			my $itemCallNumber = $finefeeList->findvalue('./xb:itemCallNumber');
			my $item_type = $finefeeList->findvalue('./xb:fineFeeType');
			my $account_number;
			if ($item_type eq 'LOSTITEMPROCESSFEE'){
				$account_number = "";
			} elsif ($item_type eq 'OVERDUEFINE'){
				$account_number = "";
			} elsif ($item_type eq 'RECALLEDOVERDUEFINE'){
				$account_number = "";
			} elsif ($item_type =~ /LOSTITEMREPLACEMENTFEE/){
				$account_number = "";
			} elsif ($item_type =~ /CUSTOMER_DEFINED_01/){ 
				$account_number = "";
			} elsif ($item_type =~ /CUSTOMER_DEFINED_02/){
                                $account_number = "";
			} else{
				$account_number = $item_type;
			}
			
			my $itemLocation = $finefeeList->findvalue('./xb:itemInternalLocation');
			my $itemDueDate = $finefeeList->findvalue('./xb:itemDueDate');
			my $itemBarcode = $finefeeList->findvalue('./xb:itemBarcode');
			my $amount = $finefeeList->findvalue('./xb:compositeSum/xb:sum');
		
			if ($EmplID =~ /^[0-9]{10}$/){
			# 12/06 use barcode as reference number	
			#	print CSVFILE "UTARL,".$EmplID.",".$account_number.",,".$amount.",,,".$bursar_trans_id."\n";	
				 print CSVFILE "UTARL,".$EmplID.",".$account_number.",,".$amount.",,,".$itemBarcode."\n";
				print LOGFILE "Patron ID: ".$EmplID."\n";
				if ($item_type =~ /CUSTOMER_DEFINED_01/){
					$item_type = "LOSTEQUIPMENTREPLACEMENTFEE" ;
				}
				if ($item_type =~ /CUSTOMER_DEFINED_02/){
                                        $item_type = "LOSTEQUIPMENTPROCESSFEE" ;
                                }

				print LOGFILE "Fine/fee type: ".$item_type."\n";
				print LOGFILE "Amount: ".$amount."\n";
				print LOGFILE "Item Title:".$itemTitle."\n";
				print LOGFILE "Item Call Number :".$itemCallNumber."\n";
				print LOGFILE "Due Date: ".$itemDueDate."\n";
				print LOGFILE "Item Barcode: ".$itemBarcode."\n\n";

			} 
			else{
				print LOGFILE "Bad Institutional ID: ".$EmplID."\n";
                                print LOGFILE "Fine/fee type: ".$item_type."\n";
                                print LOGFILE "Amount: ".$amount."\n";
                                print LOGFILE "Item Title:".$itemTitle."\n";
                                print LOGFILE "Item Call Number :".$itemCallNumber."\n";
                                print LOGFILE "Due Date: ".$itemDueDate."\n";
                                print LOGFILE "Item Barcode: ".$itemBarcode."\n\n";
			}
		
	}
	}

	
	close(XMLFILE);

	#move the processed xml file to DONE folder
	print LOGFILE "\n\nMove processed xml file to ".$xml_file_done."\n\n";

	rename ($xml_file, $xml_file_done) or print LOGFILE "ERROR: couldn't move $xml_file to $xml_file_done\n";
	
}

