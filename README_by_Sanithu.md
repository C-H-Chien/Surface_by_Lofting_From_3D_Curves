## Introduction
This is Brown University LEMS lab internal collaborative research project which aims to reconstruct surfaces from a set of 3D curves and multiple 2D images. Basically, it is a a hypothesis and verification framework, where many hypothesized surfaces are constructed from pairs of 3D curves, and are subsequently verified via projecting to multiview images to seek supports from detected 2D [third-order edges](https://github.com/C-H-Chien/Third-Order-Edge-Detector). This work has been proposed by the papers listed in references, but the source code is missing. Here, we *(i)* surrect its experiments, *(ii)* optimize the pipeline to make it super efficient, and *(iii)* run on a modern synthetic dataset, *i.e.*, [ABC dataset](https://deep-geometry.github.io/abc-dataset/) with rendered multiviews from [NEF](https://github.com/yunfan1202/NEF_code), enabling us to easy debug the entire process. <br />

## How to run for obj 00000325
- Download ABC_curves_result, ABC_NEF_obj and ABE-NEF folders [sample data](https://drive.google.com/file/d/1gYFKFiUe2GCFWLKpOgJ_s1Fn8xTjoQqE/view?usp=drive_link)
- After cloning the repo, create a folder called data.
- Build the following file heiracy usnig the data from the data folders downloaded previously:
- data/
- 
     └── object_00000325/

	├── images/           (00.jpg ... 49.jpg)   (take the images from the traini_img folder)

	├── edges/            (00.mat ... 49.mat with TO_edges) (folder with all the edges)

	├── 00.projmatrix ... 49.projmatrix

	└── curve_graph_00000325.mat     this file will be made in the following steps

     └──any other files relating to object 325 within the downloaded folders
  
- Creating curve_graph_00000325.mat:
- 
    Open get_ABC_NEF_gt_curve_points.py and change , at arounf line 90 the root_dir and base_dir accordingly:
  
      root_dir = r"{your path}\Surface_by_Lofting_From_3D_Curves\tools"
      base_dir = r"{your path}\ABC_NEF_obj"
      Near line 100 set desired_obj = "00000325".
  
      Replace the line plt.axis([range_size[0],range_size[1],range_size[0],range_size[1]])
  
        with the two lines : ax.set_xlim(range_size[0], range_size[1])
  
                              ax.set_ylim(range_size[0], range_size[1])
  
    Open main.m and update the fol;lowing lines:
  
        media_storage = ""; dataset_name = ""; dataset_path = ""; object_tag = "00000325"; save_curve_mat_file = 1;
  
        ymlPath = fullfile("{your path}\Surface_by_Lofting_From_3D_Curves\data","00000325_3062bccff48e47a2b9de05e3_features_020.yml"); [!!Ensure you have the necessary .ymlfile]
  
        at the bottom update this line:
  
                complete_curve_graph = final_curves;
  
                save(fullfile("{your path}\Surface_by_Lofting_From_3D_Curves\data", "curve_graph_00000325.mat"), "complete_curve_graph");
  
    Open Matlab and cd into Surface_by_Lofting_From_3D_Curves and run "tools/curve_sampling/main" OR download Matlab extension on VScode and press the run triangle button at the top while main.m is open

- PATH changes

      Occlusion_consistency_check: within lines 30-55 replace all 4 instances of "Amsterdam" data with the following lines:
  
            fname1 = fullfile(pwd, 'data','object_00000325', sprintf("%02d.projmatrix", view-1));                  for projection matrices
  
                    NOTE: there are 2 lines on projection Matrices, replace both
  
            fname2 = fullfile(pwd, 'data', 'object_00000325', 'images', 'edges', sprintf("%02d.mat", view-1));     for edges
  
            fname3 = fullfile(pwd, 'data', 'object_00000325', 'images', sprintf( "%02d.png", view-1));             change to png as data is png not jpeg
  
      PreProcessed_3D_Curves_main: update the line: input_curves = load(fullfile(pwd, 'data', 'curve_graph_00000325.mat')).complete_curve_graph;
  
-In matlab run main.m. curve_graph_00000325.mat  should be made now!

-In order to prevent errors from proximity pairing and lofting when attempting to run the repository make the following changes:

            in PreProcessed_3D_Curves_main : PARAMS.TAU_NUM_OF_PTS = 50;
  
            in PreProcessed_3D_Curves_main : PARAMS.BREAK = 0;
  
            in proximity_pairing : PARAMS.TAU_ALPHA = [5 150];
  
-In Matlab cd to Surface_by_Lofting_From_3D_Curves and type run in the command window

-Ensure blender\output in Surface_by_Lofting_From_3D_Curves has the .ply files

-Open blender and import these standford ply files to view
            

## Contributors
Zichang Gao (zichang_gao@brown.edu) (Research Asistant, Jul. 2023 - Dec. 2023) <br />
Chiang-Heng Chien (chiang-heng_chien@brown.edu) (Ph.D. Student, Jan. 2021 - Now) <br />
*Advisory Board:*
Prof. Benjamin Kimia (benjamin_kimia@brown.edu)
Prof. Ricardo Fabbri (rfabbri@iprj.uerj.br)

## References
``Usumezbas, Anil, Ricardo Fabbri, and Benjamin B. Kimia. "From multiview image curves to 3D drawings." In Computer Vision–ECCV 2016: 14th European Conference, Amsterdam, The Netherlands, October 11–14, 2016, Proceedings, Part IV 14, pp. 70-87. Springer International Publishing, 2016.`` ([Paper Link](https://link.springer.com/chapter/10.1007/978-3-319-46493-0_5)) <br />
``Usumezbas, Anil, Ricardo Fabbri, and Benjamin B. Kimia. "The surfacing of multiview 3d drawings via lofting and occlusion reasoning." In Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition, pp. 2980-2989. 2017.`` ([Paper Link](https://openaccess.thecvf.com/content_cvpr_2017/html/Usumezbas_The_Surfacing_of_CVPR_2017_paper.html))

## Lisence
The code in this repository is under the lisence GNU GPLv3. <br />
Please contact the authors if you have any questions.

