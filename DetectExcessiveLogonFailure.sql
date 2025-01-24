-- Script to monitor excessive failed logon attempts and send an alert
USE [master];
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_MonitorExcessiveLogonFailures] 
(
    @Duration INT,              -- Time window in minutes to check for failed logon attempts
    @AlertThreshold INT         -- Threshold for sending an alert
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Declare variables
    DECLARE @StartTime DATETIME = DATEADD(MINUTE, -@Duration, GETDATE());
    DECLARE @EndTime DATETIME = GETDATE();
    DECLARE @Html NVARCHAR(MAX) = '';
    DECLARE @Subject NVARCHAR(MAX) = 'Alert: Multiple Failed Logon Attempts Detected on ' + @@SERVERNAME;
    DECLARE @FailedLogonCount INT;

    -- Temporary table for error log data
    IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
        DROP TABLE #ErrorLog;

    CREATE TABLE #ErrorLog (
        LogDate DATETIME,
        ProcessInfo NVARCHAR(100),
        [Text] NVARCHAR(MAX)
    );

    -- Populate the temporary table with failed logon attempts from the SQL Server error log
    INSERT INTO #ErrorLog (LogDate, ProcessInfo, [Text])
    EXEC xp_readerrorlog 0, 1, N'Login failed for user', NULL, NULL, NULL, 'DESC';

    -- Count the number of failed logon attempts in the specified time window
    SELECT @FailedLogonCount = COUNT(*)
    FROM #ErrorLog
    WHERE LogDate BETWEEN @StartTime AND @EndTime;

    -- Check if the failed logon attempts exceed the alert threshold
    IF (@FailedLogonCount >= @AlertThreshold)
    BEGIN
        -- Generate the HTML table for the email body
        SELECT @Html += '<tr>'
                      + '<td>' + CAST(COUNT(*) AS NVARCHAR(55)) + '</td>' 
                      + '<td>' + CONVERT(NVARCHAR(55), MAX(LogDate), 120) + '</td>' 
                      + '<td>' + [Text] + '</td>' 
                      + '</tr>'
        FROM #ErrorLog
        WHERE LogDate BETWEEN @StartTime AND @EndTime
        GROUP BY [Text]
        ORDER BY COUNT(*) DESC;

        -- Create the full HTML body
        SET @Html = 
            N'<h4 style="font-weight: bold; color: red;">Multiple Failed Logon Attempts Detected on ' + @@SERVERNAME + '.</h4>' + 
            '<table border="1" style="padding: 5px; color: black; font-family: Segoe UI; text-align: left; border-collapse: collapse; width: 100%;">
                <tr style="font-size: 12px; font-weight: normal; background: #BABABB;">
                    <th>Failed Logon Count</th>
                    <th>Latest Logon Date</th>
                    <th>Message</th>
                </tr>' + @Html + 
            '</table>' +
            N'<p><b>Server:</b> ' + @@SERVERNAME + N'<br>
            <b>Total Logon Failure Count:</b> ' + CAST(@FailedLogonCount AS NVARCHAR(55)) + N'<br>
            <b>Job Name:</b> DBA - Eagle Eye Excessive Logon Failure Monitor<br>
            <b>Reporting Date:</b> ' + CONVERT(NVARCHAR(55), GETDATE(), 120) + N'</p>';

        -- Send the email alert
        EXEC msdb.dbo.sp_send_dbmail 
            @recipients = 'email@domain.com',
            @subject = @Subject,
            @body = @Html,
            @body_format = 'HTML';
    END
END
GO
