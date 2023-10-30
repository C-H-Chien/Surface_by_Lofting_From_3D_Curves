function [TO_edges_pos, contour_list] = read_cem_file(cem_file)
    
    cem_FileRead = fopen(cem_file, 'r');

    ldata = textscan(cem_FileRead, '%s', 'whitespace', '{}', 'CollectOutput', true);
    line = ldata{1};
     
%     %> read line by line
%     lineBuffer = fgetl(cem_file);
    
    contour_count_line = string(line(4,1));
    str_edge_num = extractAfter(contour_count_line, "=");
    edge_num = double(str_edge_num);
    
    %> initialize TO_edges
    TO_edges_pos = zeros(edge_num, 2);
    
    %> export edge info in cem file to TO_edges_pos
    for i = 1:edge_num
        y = string(line(i+4,1));
        str_y = extractBetween(y, "(", ")");
        str_pos = strsplit(str_y, ", ");
        TO_edges_pos(i,1) = double(str_pos(1,1));
        TO_edges_pos(i,2) = double(str_pos(1,2));
        
    end
    
    flag_contour_edges = 0;
    flag_contour_count = 0;
    max_edge_sz = 0;
    for i = (4+edge_num):size(line, 1)
        y = string(line(i,1));
        
        if strcmp(y, "[Contour Properties]")
            break;
        end
        
        if strcmp(y, "[Contours]")
            flag_contour_count = 1;
            continue;
        end
        
        if flag_contour_count
            y = string(line(i,1));
            str_contour_num = extractAfter(y, "=");
            contour_num = double(str_contour_num);
            contour_start_line_index = i + 1;
            flag_contour_edges = 1;
            flag_contour_count = 0;
            continue;
        end
        
        %> find the maximal edge size across all contours
        if flag_contour_edges
            str_edge_indices = extractBetween(y, "[", "]");
            edge_index_list = strsplit(str_edge_indices, " ");
            if size(edge_index_list, 2) > max_edge_sz
                max_edge_sz = size(edge_index_list, 2);
            end
        end
    end
    
    %> initialize contour list
    contour_list = zeros(contour_num, max_edge_sz);
    
    %> export contour edges from cem file to a contour list
    contours_counter = 1;
    edges_counter = 1;
    for i = contour_start_line_index:(contour_start_line_index+contour_num-1)
        y = string(line(i,1));
        str_edge_indices = extractBetween(y, "[", "]");
        edge_index_list = strsplit(str_edge_indices, " ");
        for j = 1:size(edge_index_list, 2)
            contour_list(contours_counter, edges_counter) = double(edge_index_list(1,j)) + 1;
            edges_counter = edges_counter + 1;
        end
        
        edges_counter = 1;
        contours_counter = contours_counter + 1;
        
    end
end