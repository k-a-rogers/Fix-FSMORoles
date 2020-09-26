# Fix-FSMORoles

Fix-FSMORoles is a Powershell script that implements the behaviour of fixFSMO.vbs. FixFSMO.vbs is an <a href="https://support.microsoft.com/en-gb/help/949257/error-message-when-you-run-the-adprep-rodcprep-command-in-windows-serv">old script provided by Microsoft</a> for resolving issues where domain-level FSMO role metadata becomes corrupted in AD (often as a result of forcible removal of a DC). If you don't know what FSMO roles are, <a href="https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/fsmo-roles">start here</b>.

I wrote this script for 2 reasons:
1) I needed to fix a problem with FSMO roles in a production environment, and
2) I am not particularly familiar with vbscript and wanted to ensure I understood the actions that would be taken during remediation.

I have a writeup of the original problem, along with a breakdown of how the script works, in <a href="https://powershellshocked.wordpress.com/2019/07/29/validating-fsmo-roles-and-replacing-fixfsmo-vbs-with-powershell/">this blog post</a>.
