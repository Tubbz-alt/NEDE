function [EEG, times, codes, iRemoved] = NEDE_AddEeglabEvents(y,EEG)

% Removes the current events from the EEGLAB file and replaces them with
% new ones according to the events_rule specified in the code.  Then
% re-saves the data, overwriting the old file.
%
% [EEG, times, codes, iRemoved] = NEDE_AddEeglabEvents(x,EEG)
%
% NOTES:
% - EEGLAB should already be started.  
%
% INPUTS:
% -x
% -EEG
% -output_suffix is a string specifying the end of the filename to be saved
% Full filename is '3DS-<subject>-<session><output_suffix>.set' [input_suffix]
%
% OUTPUT:
% -EEG is the output file's eeglab struct.
%
% Created 8/2/10 by DJ.
% Updated 11/5/10 by DJ - switched to OddballTask events rule
% Updated 2/23/11 by DJ - made a function. 
% Updated 2/25/11 by DJ - added threshold. 
% Updated 3/1/11 by DJ - comments
% Updated 10/27/11 by DJ - added experimentType option to work with squares
%  experiments
% Updated 10/31/11 by DJ - separated input/output suffixes.
% Updated 2/28/13 by DJ - added SquaresFix compatibility.
% Updated 3/17/13 by DJ - added SquaresFix3 compatibility.
% Updated 1/31/14 by DJ - switched to NEDE format.
% Updated 2/19/14 by DJ - fixed saccade bugs.

%% CHECK INPUTS AND SET UP

tic

% Get sync events
[eyeSyncs, eegSyncs] = NEDE_GetSyncEvents(y,EEG);
if ischar(EEG.event(1).type)
    boundaryTimes = [0, EEG.event(strmatch('boundary', {EEG.event(:).type})).latency, EEG.pnts]*1000/EEG.srate; % in seconds
else
    boundaryTimes = [EEG.xmin, EEG.xmax];
end

if ~isequal(eegSyncs(:,2),eyeSyncs(:,2)) || ~isequal(eegSyncs(:,3),eyeSyncs(:,3)) % number of events that aren't in exactly the right spot
    error('Sync events don''t match up!');
end

nSessions = length(y);
[eyeTimes,eegTimes,eyeCodes,iRemoved] = deal(cell(1,nSessions));

%% Get events times and codes
for i=1:nSessions
    x = y(i);
    % Parse inputs
    isTargetObject = strcmp('TargetObject',{x.objects(:).tag});
    % visibility events
    visible = x.events.visible;
    visible_objects = unique(visible.object);
    visible_isTarget = isTargetObject(visible_objects);
    visible_times = nan(length(visible_objects),2); 
    for j=1:numel(visible_objects)
        visible_times(j,:) = visible.time([...
            find(visible.object==visible_objects(j),1,'first'), ...
            find(visible.object==visible_objects(j),1,'last')]);
    end
    targetApp_times = visible_times(visible_isTarget,1);
    targetDisapp_times = visible_times(visible_isTarget,2);
    distApp_times = visible_times(~visible_isTarget,1);
    distDisapp_times = visible_times(~visible_isTarget,2);
    % saccade events
    saccade = x.events.saccade;
    saccadeToObj_times = saccade.time_end(saccade.isFirstToObject);
    saccadeToObj_obj = saccade.object_seen(saccade.isFirstToObject);
    saccadeToObj_isTarg = isTargetObject(saccadeToObj_obj);
    saccadeToTarg_times = saccadeToObj_times(saccadeToObj_isTarg);
    saccadeToDist_times = saccadeToObj_times(~saccadeToObj_isTarg);

    % construct matrix
    eyeTimes{i} = [targetApp_times; distApp_times; targetDisapp_times; distDisapp_times; ...
        saccadeToTarg_times; saccadeToDist_times; saccade.time_start; saccade.time_end; ...
        x.events.blink.time_start; x.events.blink.time_end; x.events.button.time; ...
        x.events.trial.time_start; x.events.trial.time_end];
    
    % Find event codes
    eyeCodes{i} = [repmat({'Targ Appear'},numel(targetApp_times),1); ...
        repmat({'Dist Appear'},numel(distApp_times),1); ...
        repmat({'Targ Disapp'},numel(targetDisapp_times),1); ...
        repmat({'Dist Disapp'},numel(distDisapp_times),1); ...
        repmat({'Targ Sacccade'},numel(saccadeToTarg_times),1); ...
        repmat({'Dist Saccade'},numel(saccadeToDist_times),1); ...
        repmat({'Saccade Start'},numel(saccade.time_start),1); ...
        repmat({'Saccade End'},numel(saccade.time_end),1); ...
        repmat({'Blink Start'},numel(x.events.blink.time_start),1); ...
        repmat({'Blink End'},numel(x.events.blink.time_end),1); ...
        repmat({'Button Press'},numel(x.events.button.time),1); ...
        repmat({'Trial Start'},numel(x.events.trial.time_start),1); ...
        repmat({'Trial End'},numel(x.events.trial.time_end),1); ];

    isInSession_sync = eyeSyncs(:,3)==i;
    eegTimes{i} = interp1(eyeSyncs(isInSession_sync,1),eegSyncs(isInSession_sync,1),double(eyeTimes{i}),'linear','extrap');
    iRemoved{i} = find(eegTimes{i}<boundaryTimes(i) | eegTimes{i}/EEG.srate>boundaryTimes(i+1));
    
    fprintf('Session %d: removing %d events\n',i,numel(iRemoved{i}));
    eegTimes{i}(iRemoved{i}) = [];
    if ~isempty(eyeCodes)
        eyeCodes{i}(iRemoved{i}) = [];
    end
end



%% Concatenate results
nEvents = numel(cat(1,eegTimes{:}));
times = reshape(cat(1,eegTimes{:}),nEvents,1)/1000; % get time in seconds
if ~isempty(eyeCodes)
    codes = reshape(cat(1,eyeCodes{:}),nEvents,1);
else
    codes = repmat({'event'},size(times));
end

%% sort results
[times,order] = sort(times,'ascend');
codes = codes(order);

%% Get events matrix and import into EEGLAB struct
if ~isempty(eyeCodes) % only actually import events if codes are specified.
    events = [num2cell(times), codes]; % the times (in s) and codes of each event
    assignin('base','events',events); % eeglab's importevent function grabs variable from base workspace
    EEG = pop_importevent( EEG, 'append','yes','event','events','fields',{'latency' 'type'},'timeunit',1,'optimalign','off');
    EEG = eeg_checkset( EEG );
end

toc