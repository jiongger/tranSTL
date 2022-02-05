function [] = preprocess(path, historical_length, future_length, number_of_agents, max_vertical_distance, extra_feature_index)
    %% Process dataset into mat file %%

    % essential feature include:
    % 1. Dataset ID (generated by this script !NOT included in *_tracks.csv files!)
    % 2. Vehicle ID (row 2 in raw *_tracks.csv files)
    % 3. Frame ID (row 1 in raw *_tracks.csv files)
    % 4. Local X (row 3 in raw *_tracks.csv files)
    % 5. Local Y (row 4 in raw *_tracks.csv files)
    % 6. Lane ID (row 25 in raw *_tracks.csv files, dropped in post-process)
    % NOTE: X represents VERTICAL(vehicle forward) position in this dataset
    essential_feature_index = [1,3,2,5,4,26];

    % numbers in extra_feature_index represent index of rows in raw *_tracks.csv
    % e.g. extra_feature_index = [1,2], where 1 represents vehicle id and 2 represents frame id in raw *_tracks.csv files
    % but DO NOT submit duplicated index and index already in essential_feature_index
    % specially, vehicle class is not in *_tracks.csv file, assign 26 if you want to acquire vehicle class

    %% Fields - traj:
    % 1. Dataset ID
    % 2. Vehicle ID
    % 3. Frame ID
    % 4. Local X
    % 5. Local Y
    % 6. - 5+len(extra_feature_index). Extra features [optional]
    % 6+len(extra_feature_index). - 6+len(extra_feature_index)+number_of_agents. Adjacent vehicle IDs

    %% Fields - tracks:
    % 1. Frame ID
    % 2. Local X
    % 3. Local Y
    % 4. - 3+len(extra_feature_index). Extra features [Optional]
    % 4+len(extra_feature_index). Maneuver class id

    % DO NOT change following variables
    if ~isempty(extra_feature_index)
        extra_feature_index = extra_feature_index + 1;
    end
    feature_index = [essential_feature_index, extra_feature_index];
    number_of_features = length(extra_feature_index) + 2;
    lane_id_ind = 6;
    maneuver_ind = 7 + length(extra_feature_index);
    adjacent_ind = 8 + length(extra_feature_index);
    number_of_maneuvers = 9;
    padding_idx = -1;
    % set random seed = 42; 
    rng(42);

    %% Load data and add dataset id%% load data
    addpath(path);
    disp('loading data')
    trackFiles = dir(fullfile(path, '*_tracks.csv'));
    if any(extra_feature_index == 27)
        metaFiles = dir(fullfile(path, '*_tracksMeta.csv'));
        assert(length(trackFiles) == length(metaFiles), "Missing meta file(s)")
    end

    for ii = 1:length(trackFiles)
        fprintf('loading dataset %d\n',ii)
        trackname = fullfile(path, trackFiles(ii).name);
        tracks = table2array(readtable(trackname, 'Delimiter', ','));
        % convert meter to feet
        tracks(:, 3:13) = tracks(:, 3:13) / 0.3048;

        if any(extra_feature_index == 27)
            metaname = fullfile(path, metaFiles(ii).name);
            meta = readtable(metaname, 'Delimiter', ',');
            vehIds = table2array(meta(:, 1));
            vehClass = table2array(meta(:, 7));
            classes = [];
            vehCounts = hist(tracks(:, 2), vehIds);

            for jj = 1:length(vehCounts)
                if vehClass(jj) == "Car"
                    classes = [classes; 2*ones(vehCounts(jj), 1)];
                else
                    classes = [classes; 3*ones(vehCounts(jj), 1)];
                end
            end
            tracks = [ii*ones(size(tracks, 1), 1), tracks, classes];
        else
            tracks = [ii*ones(size(tracks, 1), 1), tracks];
        end

        traj{ii} = tracks(:, feature_index);
        vehTrajs{ii} = containers.Map;
        vehTimes{ii} = containers.Map;
    end

    % remove vehicles with unexcepted lane id
    traj{26}(traj{26}(:, lane_id_ind) == 5, :) = [];

    %% Parse fields (listed above):
    disp('Parsing fields...')

    for ii = 1:length(trackFiles)
        vehIds = unique(traj{ii}(:,2));
        for v = 1:length(vehIds)
            vehTrajs{ii}(int2str(vehIds(v))) = traj{ii}(traj{ii}(:,2) == vehIds(v),:);
        end

        timeFrames = unique(traj{ii}(:,3));
        for v = 1:length(timeFrames)
            vehTimes{ii}(int2str(timeFrames(v))) = traj{ii}(traj{ii}(:,3) == timeFrames(v),:);
        end

        number_of_lanes = length(unique(traj{ii}(:,lane_id_ind)));
        traj{ii}(:,maneuver_ind:adjacent_ind+number_of_agents-1) = -1;
 
        for k = 1:length(traj{ii}(:,1))
            if mod(k,10000) == 0
                fprintf('Processing dataset %d [%2.2f%%]\n', ii, k/length(traj{ii}(:,1))*100)
            end
            time = traj{ii}(k,3);
            dsId = traj{ii}(k,1);
            vehId = traj{ii}(k,2);
            vehtraj = vehTrajs{ii}(int2str(vehId));
            ind = find(vehtraj(:,3)==time);
            ind = ind(1);

            % Get lateral maneuver:
            ub = min(size(vehtraj,1),ind+future_length);
            lb = max(1, ind-historical_length);
            if vehtraj(ub,lane_id_ind)>vehtraj(ind,lane_id_ind) || vehtraj(ind,lane_id_ind)>vehtraj(lb,lane_id_ind)
                lateral = 3;
            elseif vehtraj(ub,lane_id_ind)<vehtraj(ind,lane_id_ind) || vehtraj(ind,lane_id_ind)<vehtraj(lb,lane_id_ind)
                lateral = 2;
            else
                lateral = 1;
            end
            % Get longitudinal maneuver:
            ub = min(size(vehtraj,1),ind+future_length);
            lb = max(1, ind-historical_length);
            if ub==ind || lb ==ind
                longitudinal = 1;
            else
                vHist = sqrt((vehtraj(ind,5)-vehtraj(lb,5))^2+(vehtraj(ind,4)-vehtraj(lb,4))^2)/(ind-lb);
                vFut = sqrt((vehtraj(ub,5)-vehtraj(ind,5))^2+(vehtraj(ub,4)-vehtraj(ind,4))^2)/(ub-ind);
                if vFut/vHist < 0.8
                    longitudinal = 2;
                elseif vFut/vHist > 1.25
                    longitudinal = 3;
                else
                    longitudinal = 1;
                end
            end
            % Generate maneuver class
            traj{ii}(k,maneuver_ind) = (longitudinal-1)*3 + lateral-1;

            % get adjacent vehicle ids
            frame = vehTimes{ii}(int2str(time));
            frameAdjacent = frame(abs(frame(:,5)-traj{ii}(k,5)) <= max_vertical_distance, :);
            % pick vehicles on same direction
            if number_of_lanes == 4
                if traj{ii}(k,lane_id_ind) == 2 || traj{ii}(k,lane_id_ind) == 3
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 2 | frameAdjacent(:,lane_id_ind) == 3, :);
                elseif traj{ii}(k,lane_id_ind) == 5 || traj{ii}(k,lane_id_ind) == 6
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 5 | frameAdjacent(:,lane_id_ind) == 6, :);
                else
                    error("EXTRA_LANE_ID_ERROR:"+int2str(traj{ii}(k,lane_id_ind))+"-"+int2str(ii)+"-"+int2str(vehId));
                end
            elseif number_of_lanes == 6
                if traj{ii}(k,lane_id_ind) == 2 || traj{ii}(k,lane_id_ind) == 3 || traj{ii}(k,lane_id_ind) == 4
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 2 | frameAdjacent(:,lane_id_ind) == 3 | frameAdjacent(:,lane_id_ind) == 4, :);
                elseif traj{ii}(k,lane_id_ind) == 6 || traj{ii}(k,lane_id_ind) == 7 || traj{ii}(k,lane_id_ind) == 8
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 6 | frameAdjacent(:,lane_id_ind) == 7 | frameAdjacent(:,lane_id_ind) == 8, :);
                else
                    error("EXTRA_LANE_ID_ERROR:"+int2str(traj{ii}(k,lane_id_ind))+"-"+int2str(ii)+"-"+int2str(vehId));
                end
            elseif number_of_lanes == 7
                if traj{ii}(k,lane_id_ind) == 2 || traj{ii}(k,lane_id_ind) == 3 || traj{ii}(k,lane_id_ind) == 4 || traj{ii}(k,lane_id_ind) == 5
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 2 | frameAdjacent(:,lane_id_ind) == 3 | frameAdjacent(:,lane_id_ind) == 4 | frameAdjacent(:,lane_id_ind) == 5, :);
                elseif traj{ii}(k,lane_id_ind) == 7 || traj{ii}(k,lane_id_ind) == 8 || traj{ii}(k,lane_id_ind) == 9
                    frameAdjacent = frameAdjacent(frameAdjacent(:,lane_id_ind) == 7 | frameAdjacent(:,lane_id_ind) == 8 | frameAdjacent(:,lane_id_ind) == 9, :);
                else
                    error("EXTRA_LANE_ID_ERROR:"+int2str(traj{ii}(k,lane_id_ind))+"-"+int2str(ii)+"-"+int2str(vehId));
                end
            else
                error("NUMBER_OF_LANES_ERROR:"+int2str(ii));
            end

            % pick vehicles with complete track
            adjID = -1*ones(1,number_of_agents);
            num_adjs = 0;
            for v = 1:size(frameAdjacent,1)
                vtraj = vehTrajs{ii}(int2str(frameAdjacent(v,2)));
                vind = find(vtraj(:,3)==time);
                if vind > historical_length && vind + future_length <= length(vtraj)
                    num_adjs = num_adjs + 1;
                    adjID(num_adjs) = frameAdjacent(v,2);
                end
            end
            % sort adjacent vehicle ids by distance
            dist = 999*ones(1,num_adjs);
            for i = 1:num_adjs
                vehT = vehTrajs{ii}(int2str(adjID(i)));
                vehX = vehT(vehT(:, 3) == time, 4);
                vehY = vehT(vehT(:, 3) == time, 5);
                dist(i) = sqrt((vehX-traj{ii}(k,4))^2+(vehY-traj{ii}(k,5))^2);
            end
            [~, dist_ind] = sort(dist);
            adjID(1:num_adjs) = adjID(dist_ind);

            traj{ii}(k,adjacent_ind:adjacent_ind+number_of_agents-1) = adjID;

        end

        % remove lane id
        traj{ii}(:,lane_id_ind) = [];
        fprintf('done processing dataset %d\n', ii)
    end

    %% Mapping tracks to {dataset id, vehicle id}
    disp('Mapping tracks to 2d-cell {dataset id, vehicle id}...');
    clear vehTrajs;
    clear vehTimes;
    tracks = {};
    trajAll = [];
    for k = 1:length(trackFiles)
        vehIds = unique(traj{k}(:, 2));
        trajAll = [trajAll; traj{k}];
        for l = 1:length(vehIds)
            vehTrack = traj{k}(traj{k}(:, 2)==vehIds(l), :);
            if size(vehTrack,1) > historical_length + future_length
                tracks{k,vehIds(l)} = vehTrack(:, 3:4+number_of_features); % features and maneuver class id
            else
                tracks{k,vehIds(l)} = [];
            end
        end
    end
    trajAll(:, maneuver_ind-1) = [];
    clear traj;

    %% Filter edge cases: 
    % Since the model uses 3 sec of trajectory history for prediction, the initial 3 seconds of each trajectory is not used for training/testing
    disp('Filtering edge cases...')
    Inds = zeros(size(trajAll,1), 1);
    for k = 1:size(trajAll,1)
        if isempty(tracks{trajAll(k,1),trajAll(k,2)})
            continue
        end
        if tracks{trajAll(k,1),trajAll(k,2)}(historical_length+1,1) <= trajAll(k,3) && tracks{trajAll(k,1),trajAll(k,2)}(end,1) > trajAll(k,3) + future_length
            Inds(k) = 1;
        end
    end
    trajAll = trajAll(Inds==1,:);

    %% Split train, validation, test
    disp('Splitting into train, validation and test sets...')

    splits = rand(1, size(trajAll, 1));
    trajTr = trajAll(splits <= 0.7, :);
    trajVal = trajAll((splits > 0.7) & (splits <= 0.8), :);
    trajTs = trajAll(0.8 < splits, :);


    %% Save mat files:
    disp('Saving mat files...')

    traj = trajTr;
    save('TrainSetT','traj','tracks','historical_length','future_length','number_of_agents','number_of_features','max_vertical_distance','padding_idx','number_of_maneuvers');

    traj = trajVal;
    save('ValSetT','traj','tracks','historical_length','future_length','number_of_agents','number_of_features','max_vertical_distance','padding_idx','number_of_maneuvers');

    traj = trajTs;
    save('TestSetT','traj','tracks','historical_length','future_length','number_of_agents','number_of_features','max_vertical_distance','padding_idx','number_of_maneuvers');

end
