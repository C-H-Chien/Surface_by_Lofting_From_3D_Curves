clear;

input_curves = load(fullfile(pwd, 'tmp', 'preProcessedCurves.mat')).preProcessedCurves.points;
pairs = load(fullfile(pwd, 'tmp', 'curves_proximity_pairs')).curves_proximity_pairs;

if ~exist(fullfile(pwd, 'blender', 'input'), 'dir')
   mkdir(fullfile(pwd, 'blender', 'input'))
end
if ~exist(fullfile(pwd, 'blender', 'output'), 'dir')
   mkdir(fullfile(pwd, 'blender', 'output'))
end

% save curves as txt
formatSpec = '%.10f %.10f %.10f\n';
for i = 1:size(input_curves, 2)
    curve = input_curves{i};
    fname = fullfile(pwd, 'blender', 'input',  "c" + int2str(i) + "_normal.txt");
    fileID = fopen(fname,'w');
    fprintf(fileID, formatSpec,curve');
    fclose(fileID);

    fname = fullfile(pwd, 'blender', 'input', "c" + int2str(i) + "_reverse.txt");
    fileID = fopen(fname, 'w');
    reverse = flip(curve);
    fprintf(fileID, formatSpec,reverse');
    fclose(fileID);
end

fname = fullfile(pwd, 'blender', 'input', "relation.txt");
fileID = fopen(fname,'w');
fprintf(fileID, '%d %d\n',(pairs(:, [1 2]))');
fclose(fileID);

% system("/Applications/Blender.app/Contents/MacOS/Blender --python ./blender/loft.py");