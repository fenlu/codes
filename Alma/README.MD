Bursar Transfer Scripts for Alma

As part of a library’s process, patrons can be charges with various fines and fees. At UTA, the Bursar Office handles all patron-related charges in its own system. We can export fine and fee information from Alma as an XML file. This script is to convert Alma generated XML file to a CSV file format that our bursar system can ingest. The script adds library account information based on the fine/fee type. For example, overdue fines, general replacement fee and processing fee go the library book account. The equipment replacement fee and processing fee go to the LST account. After finishing the conversion, a detailed fine/fee report would be generated and emailed to library staff for further processing.

==========================================

Student Information System (SIS) 

SIS is the system in which the institution’s users are saved, managed and maintained. These users include faculty, staff, students, retired faculty and other affiliated people. Alma needs to know the user’s information in order to provide them library services. The user information should be copied from the SIS into Alma and synchronized on a regular basis.

This script runs daily, and it converts OIT exported CSV file containing all active user records to zipped XML files that can be imported to Alma. As in Alma each user can only be assigned to one user group, this script also merges all the records for the same user, performs comparison and assigns him/her to the group with the highest borrowing privilege. For example, a user is a UTA faculty and also a UTA graduate. This script would merge two user records so this user can log in Alma with his/her faculty email address and also his/her student email address. And it would assign this user to faculty group as faculty group has higher borrowing privileges than graduate group.
