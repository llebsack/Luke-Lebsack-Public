-- =============================================
-- Authors:    Luke Lebsack
-- Create date: 10/23/2023
-- Description:  B.I. table used to pull finacial data from PowerPlan accounting software.
--        The View pulls actual financial results, budgets and forecasts by department and account code.
--
-- Source Tables:  12MonthCloseDB.DBO.BudgetNormal  
--          12MonthCloseDB.DBO.Account
--          12MonthCloseDB.DBO.Entity
--          12MonthCloseDB.DBO.Bracket
-- Destination View:  12MonthCloseDB.DBO.Budget_BI    



USE [12MonthCloseDB]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

 
CREATE view [dbo].[Budget_BI] as 

WITH budget
     AS (
        SELECT
        --CONCAT(a.wEntityId,'_',a.wBracket,'_',a.wperiod,'_',a.wYear,'_',a.[wAccountId],'_',a.[wExtDimId1]) as Budget_upload_id -- Unique identifier used for data verification but removed for performance optimization
        a.[sentity]      AS entity,
        c.[sentityname]  AS entity_name,
        c.[sentitytype]  AS entity_type,
        c.[sentityactive],
        a.[wtimeid]      AS Fiscal_Date,
        a.[wyear]        AS year,
        a.[wperiod]      AS period,
        ( CASE
            WHEN a.[wperiod] = 1 THEN 'Jan'
            WHEN a.[wperiod] = 2 THEN 'Feb'
            WHEN a.[wperiod] = 3 THEN 'March'
            WHEN a.[wperiod] = 4 THEN 'April'
            WHEN a.[wperiod] = 5 THEN 'May'
            WHEN a.[wperiod] = 6 THEN 'June'
            WHEN a.[wperiod] = 7 THEN 'July'
            WHEN a.[wperiod] = 8 THEN 'Aug'
            WHEN a.[wperiod] = 9 THEN 'Sep'
            WHEN a.[wperiod] = 10 THEN 'Oct'
            WHEN a.[wperiod] = 11 THEN 'Nov'
            WHEN a.[wperiod] = 12 THEN 'Dec'
            ELSE 'Other'
          END )          AS Fiscal_Month -- assigns month to period, matching naming schema in PowerPlan
        ,
        a.[saccount]     AS account,
        b.[saccountname] AS account_name,
        a.[wbracket]     AS ScenarioId,
        d.[sbracketname] Scenario_Name,
        a.[scurrency]    AS amount_type,
        dvalue           AS amount,
        [dfactvalue],
        a.[wentityid],
        a.[waccountid],
        b.[saccounttype],
        a.[wextdimid1]
         FROM   budgetnormal A
                JOIN account B
                  ON a.waccountid = B.waccountid
                JOIN entity C
                  ON a.wentityid = c.wentityid
                LEFT JOIN dbo.brackets D
                       ON a.wbracket = d.[wbracket]
         WHERE  ( a.wyear = Year(Dateadd(MM, -1, Getdate()))
                   -- All Scenarios from current fiscal year. Filtered further in "current_period" is defined
                   OR ( a.wyear = Year(Dateadd(MM, -13, Getdate()))
                        -- Actuals from prior fiscal year
                        AND a.wbracket = '0' )
                   OR ( a.wyear = Year(Dateadd(MM, +11, Getdate()))
                        -- Budget from next fiscal Year
                        AND a.wbracket = '1' ) )
                AND c.[sentitytype] = 'B'),

-- Establishes what the current period is in the database for the current year
     current_period
     AS (
        SELECT
			 ( CASE
                   WHEN current_id = 1 THEN 'Jan'
                   WHEN current_id = 2 THEN 'Feb'
                   WHEN current_id = 3 THEN 'March'
                   WHEN current_id = 4 THEN 'April'
                   WHEN current_id = 5 THEN 'May'
                   WHEN current_id = 6 THEN 'June'
                   WHEN current_id = 7 THEN 'July'
                   WHEN current_id = 8 THEN 'Aug'
                   WHEN current_id = 9 THEN 'Sep'
                   WHEN current_id = 10 THEN 'Oct'
                   WHEN current_id = 11 THEN 'Nov'
                   WHEN current_id = 12 THEN 'Dec'
                   ELSE 'Other'
                 END )            AS previous_month,
               current_id         AS current_period,
               ( current_id + 1 ) AS test_period,
               ( CASE
                   WHEN ( current_id + 1 ) = 1 THEN 'Jan'
                   WHEN ( current_id + 1 ) = 2 THEN 'Feb'
                   WHEN ( current_id + 1 ) = 3 THEN 'March'
                   WHEN ( current_id + 1 ) = 4 THEN 'April'
                   WHEN ( current_id + 1 ) = 5 THEN 'May'
                   WHEN ( current_id + 1 ) = 6 THEN 'June'
                   WHEN ( current_id + 1 ) = 7 THEN 'July'
                   WHEN ( current_id + 1 ) = 8 THEN 'Aug'
                   WHEN ( current_id + 1 ) = 9 THEN 'Sep'
                   WHEN ( current_id + 1 ) = 10 THEN 'Oct'
                   WHEN ( current_id + 1 ) = 11 THEN 'Nov'
                   WHEN ( current_id + 1 ) = 12 THEN 'Dec'
                   ELSE 'Other'
                 END )            AS current_month,
               current_scenario,
               current_year
         FROM   (SELECT
						Max(a.wperiod)  AS current_id,
                        sbracketname    AS current_scenario,
                        Year(Getdate()) AS current_year
                 FROM   [budgetnormal] a
                        JOIN dbo.brackets b
                          ON a.wbracket = b.wbracket
                 WHERE  [sentity] = '91010'
                        AND [saccount] = '10-3111'
                        AND a.[wbracket] = '0'
                        AND a.wyear = Year(Dateadd(MM, -1, Getdate()))
                 GROUP  BY sbracketname) AS curr_mon)

-- Combines Actuals and FCST to create FY FCST | Pulls prior fcst, actuals, prior year and budget scenarios from the budget data set 
SELECT	       
			   c.previous_month,
               c.current_month,
               CASE
                 WHEN a.scenario_name IN ( 'ACTUAL', 'FCT' )
                      AND a.year = c.current_year THEN 'FY FCST'
                 WHEN a.scenario_name = c.previous_month THEN 'Prior FCST'
                 WHEN a.year = Year(Dateadd(month, -13, Getdate())) THEN
                 'Prior Year'
                 WHEN a.scenario_name = 'Budget' THEN 'Plan'
                 ELSE a.scenario_name
               END AS Scenario_Formatted, -- Renames scenarios to match current schema
               a.*
FROM   budget a
       LEFT JOIN current_period c
              ON a.year = c.current_year
-- Filters on current FY FCST, Prior FY FCST, Prior Year Actuals, Current Budget, and Future year Budget
WHERE  ( ( (( a.scenarioid IN ( '1' )
               OR ( a.scenarioid = '3'
                    AND a.year = Year(Dateadd(MM, +11, Getdate())) )
               OR ( a.scenarioid = '2'
                    AND a.period > c.current_period
                   -- Defines Forecast periods in FY FCST
                   )
               OR a.scenarioid = '0'
                  AND a.period <= c.current_period
             -- Defines Actuals periods in FY FCST
             ))
            OR a.scenario_name = c.previous_month )
          OR a.scenarioid = '0' )


GO