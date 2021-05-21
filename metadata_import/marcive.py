#!/usr/local/bin/python3

import sys
import os
import io
import pysftp
from pymarc import MARCReader
import csv
from datetime import datetime

def marcive_sftp(dir,log):
    #retrieve files from marcive server  
    with pysftp.Connection('web.marcive.com', username='xxxxxx', password='xxxxxxx') as sftp:
        log.write('Connection succesfully stablished ...\n')
        sftp.cwd('output/ftp/xxxxxxx')
        list = sftp.listdir()
        print(list)
        os.chdir(dir)
        for i in list:
            sftp.get(i)
            log.write("Downloaded file <"+i+">\n")
        sftp.close()
        log.write("Close the SFTP connection!\n")

def main():
    # receipients of processing results
    # mail_rcp = 'fenlu@uta.edu'
    
    # get the current date and time
    now = datetime.now()
    date = now.strftime("%m%d%Y")

    downloadDir = '/marciveFiles/download'
    processedDir = '/marciveFiles/processed'
    logDir = '/marciveFiles/logs'
    fileName = "Marcive_list_"+date+".csv"
    logFileName = "log_"+date+".log"
 
    log = open(f"{logDir}/{logFileName}", 'w', encoding='utf-8')
    csvfile = open(f"{processedDir}/{fileName}", 'w', encoding='utf-8')

    #marcive_sftp(dir=downloadDir, log=log)
    f = csv.writer(csvfile)
    f.writerow(["Titile","Call Number","GPO Item Number","OCLC Number"])
    for i in os.listdir(downloadDir):
        if "G127" in i:
            os.chdir(downloadDir)
            log.write("Start to process the file <"+i+">\n")
            counter = 0
            with open(i,'rb') as fh:
                counter = counter +1
                reader = MARCReader (fh)
                for record in reader:
                    #print(record)
                    if record['245'] is not None:
                        field245 = record['245']['a']
                    else:
                        field245 = ""
                    if record['086'] is not None:
                        field086 = record['086']['a']
                    else:
                        field086 = ""
                    if record['074'] is not None:
                        field074= record['074']['a']
                    else:
                        field074 = ""
                    if record['001'] is not None:
                        field001 = record['001'].value()
                    else:
                        field001 = ""
                    f.writerow([field245, field086, field074, field001])
                
            log.write("Finished processing file<"+i+"> There are "+str(counter)+" records. \n")
        os.system(f'mv {downloadDir}/{i} {processedDir}/{i}')
    csvfile.close()

if __name__ == "__main__":
    main()
