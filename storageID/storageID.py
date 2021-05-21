#!/usr/bin/env python3

import requests
import configparser
import xmltodict
import pprint
#import xml.etree.ElementTree as ET
import json
import os
from datetime import datetime
import sys
from requests import Session

def main():
    # read configurations ##############################################################
    config = configparser.ConfigParser()
    config.read('config.ini')
    apikey = config['misc']['apikey']
    set_id = config['misc']['set_id']
    limit = config['misc']['limit']
    offset = config['misc']['offset']

    # get the current date and time
    now = datetime.now()
    date = now.strftime("%m%d%Y")

    # create a log file, one day one log file
    # log file records bib_id, holding_id, item_id, barcode
    log_FileName = "storageLocationID_" + date + ".log"
    log = open(log_FileName, "a") if os.path.exists(log_FileName) else open(log_FileName, "w")
    log.write("\n\nThe set ID is "+set_id+"    The current time is:"+ now.strftime("%m/%d/%Y, %H:%M:%S")+" ---------------------\n")

    # create an error log file, one day one error log file
    # error log records request_url, response_data, error code and message
    errorLog_FileName = "error_"+date+".log"
    errorLog = open(errorLog_FileName, "a") if os.path.exists(errorLog_FileName) else open(errorLog_FileName, "w")
    errorLog.write("\n\nThe set ID is "+set_id+" and the current time  is "+ now.strftime("%m/%d/%Y, %H:%M:%S")+"----------------------------\n")

    # Setup requests session
    session = Session()
    session.headers.update({
        'accept': 'application/json',
        'authorization': 'apikey {}'.format(apikey)
    })

    # API doc https://developers.exlibrisgroup.com/alma/apis/docs/conf/R0VUIC9hbG1hd3MvdjEvY29uZi9zZXRzL3tzZXRfaWR9L21lbWJlcnM=/
    # Retrieve a set of members

    setQueryUrl = f"https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/sets/{set_id}/members"
    retry = 0

    while (int(offset)<5000) and (retry<10) :
        # Limit: the number of results. Optional. Valid values are 0-100. Default value: 10.
        # Offset of the results returned. Optional. Default value: 0, which means that the first results will be returned.
        setQueryParams = {
            "limit": limit,
            "offset": offset
        }
        print(f"{offset}")
        try:
            responseToSetQuery = session.get(setQueryUrl, params=setQueryParams, timeout=10)
        except requests.exceptions.RequestException as err:
            errorLog.write("Exception: "+str(err)+"\n")
            retry = retry +1
            continue
        
        # check for errors
        errorLog.write("\n")
        if check_errors(responseToSetQuery, errorLog, log):
            continue
        
        #print("Set query request:---------")
        #printReqResult(responseToSetQuery)
        
        members = json.loads(responseToSetQuery.text)
        offset = int(offset)+int(limit)
        if 'member' not in members:
            sys.exit("It's an empty set")
        for child in members['member']:

            # get each item's link
            itemurl = child.get('link')

            # restrieve an item in json format
            print(itemurl)

            try:
                responseToItemQuery = session.get(itemurl, timeout=10)
            except requests.exceptions.RequestException as err:
                errorLog.write("Exception message: "+format(err)+"\n")
                retry = retry +1
                continue
            if check_errors(responseToItemQuery, errorLog, log):
                continue
            #print("\nMembers query request:---------")
            #printReqResult(responseToItemQuery)

            jsonData = json.loads(responseToItemQuery.text)
            mms_id = jsonData["bib_data"]["mms_id"]
            holding_id = jsonData["holding_data"]["holding_id"]
            item_id = jsonData["item_data"]["pid"]
            barcode = jsonData["item_data"]["barcode"]

            log.write(mms_id+"\t"+ holding_id + "\t"+ item_id +"\t"+barcode)
            item_json = jsonData["item_data"]
            # if storage_location_id field is empty, copy information from internal_notes 3 over
            if not item_json["storage_location_id"]:
                internal_note_3 = item_json["internal_note_3"].upper()
                if "RAN" in internal_note_3:
                    if internal_note_3.startswith("RAN"):
                        item_json["storage_location_id"] = internal_note_3
                    else:
                        RANindex = internal_note_3.index("RAN")
                        item_json["storage_location_id"] = internal_note_3[RANindex:(RANindex+14)]
                    log.write("\t"+item_json["storage_location_id"]+"\n")
                    if "bib_data" in jsonData:
                        del jsonData["bib_data"]
                    jsonData["link"] = itemurl
                    headers = {
                        'Content-Type': 'application/json;charset=UTF-8'
                    }
                    #print(jsonData)
                    try:
                        responseToUpdateItem = session.put(itemurl, headers=headers, data=json.dumps(jsonData), timeout=120)
                    except requests.exceptions.RequestException as err:
                        errorLog.write("Exception message: "+format(err)+"\n")
                        retry = retry +1
                        continue
                    if check_errors(responseToUpdateItem, errorLog, log):
                        continue
            else:
                log.write("\n")

    errorLog.close()
    log.close()

    # update offset in configuration file (for itemlized set)
    #config['misc']['offset'] = str(int(offset) + int(limit))
    #with open('config.ini', 'w') as configfile:
    #    config.write(configfile)


def printReqResult(resData):
    print("Status code:{0}".format(resData.status_code))
    print("\n")
    print("Header: {0}".format(resData.headers))
    print("\n")
    print("Data:")
    print(resData.text)


def check_errors(r, errorLog, log):
    errorLog.write("Request URL: "+r.url+"\n")
    errorLog.write(r.text+"\n")
    if r.status_code != 200:
        
        if "application/json" in r.headers['content-type']:
            errorJson = json.loads(r.text)            
            errorCode = errorJson['web_service_result']['errorList']['error']['errorCode']
            errorMessage = errorJson['web_service_result']['errorList']['error']['errorMessage']

        else:
            errorXML = xmltodict.parse(r.text)
            errorCode = errorXML['web_service_result']['errorList']['error']['errorCode']
            errorMessage = errorXML['web_service_result']['errorList']['error']['errorMessage']
        errorLog.write("Error code: "+errorCode+"\n")
        errorLog.write("Error message: "+errorMessage+"\n")
        return True
        #errorLog.close()
        #log.close()
        #sys.exit(errorMessage)
    else:
        return False

if __name__ == "__main__":
    main()
