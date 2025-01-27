-- Script to monitor excessive failed Login attempts and send an alert
USE [master];
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_MonitorExcessiveLoginFailures] 
(
    @Duration INT,              -- Time window in minutes to check for failed Login attempts
    @AlertThreshold INT         -- Threshold for sending an alert
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Declare variables
    DECLARE @StartTime DATETIME = DATEADD(MINUTE, -@Duration, GETDATE());
    DECLARE @EndTime DATETIME = GETDATE();
    DECLARE @Html NVARCHAR(MAX) = '';
    DECLARE @Subject NVARCHAR(MAX) = 'Alert: Multiple Failed Login Attempts Detected on ' + @@SERVERNAME;
    DECLARE @FailedLoginCount INT;

    -- Temporary table for error log data
    IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
        DROP TABLE #ErrorLog;

    CREATE TABLE #ErrorLog (
        LogDate DATETIME,
        ProcessInfo NVARCHAR(100),
        [Text] NVARCHAR(MAX)
    );

    -- Populate the temporary table with failed login attempts from the SQL Server error log
    INSERT INTO #ErrorLog (LogDate, ProcessInfo, [Text])
    EXEC xp_readerrorlog 0, 1, N'Login failed for user', NULL, NULL, NULL, 'DESC';

    -- Count the number of failed login attempts in the specified time window
    SELECT @FailedLoginCount = COUNT(*)
    FROM #ErrorLog
    WHERE LogDate BETWEEN @StartTime AND @EndTime;

    -- Check if the failed login attempts exceed the alert threshold
    IF (@FailedLoginCount >= @AlertThreshold)
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
            N'<h4 style="font-weight: bold; color: red;">Multiple Failed Login Attempts Detected on ' + @@SERVERNAME + '.</h4>' + 
			 N'<p><b>Server:</b> ' + @@SERVERNAME + N'<br>
            <b>Total Login Failure Count:</b> ' + CAST(@FailedLoginCount AS NVARCHAR(55)) + N'<br>
            <b>Job Name:</b> DBA - Eagle Eye Excessive Login Failure Monitor<br>
            <b>Reporting Date:</b> ' + CONVERT(NVARCHAR(55), GETDATE(), 120) + N'</p>' +
            '<table border="1" style="padding: 5px; color: black; font-family: Segoe UI; text-align: left; border-collapse: collapse; width: 100%;">
                <tr style="font-size: 12px; font-weight: normal; background: #BABABB;">
                    <th>Failed Login Count</th>
                    <th>Latest Login Date</th>
                    <th>Message</th>
                </tr>' + @Html + 
            '</table>' 
        
        -- Send the email alert
        EXEC msdb.dbo.sp_send_dbmail 
            @recipients = 'athena.sql.lab@outlook.com',
            @subject = @Subject,
            @body = @Html,
            @body_format = 'HTML';
    END
END
GO
