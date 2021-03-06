/* Module file taken "AS-IS" and adapted to FEMPAR needs from p4est_wrapper.h
   https://github.com/cburstedde/hopest 4feed803f0c61564203a7bc3f2ca1a6adb63d3cd */
/*
  This file is part of hopest.
  hopest is a Fortran/C library and application for high-order mesh
  preprocessing and interfacing to the p4est apaptive mesh library.

  Copyright (C) 2014 by the developers.

  hopest is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  hopest is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with hopest; if not, write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

#ifdef ENABLE_P4EST

#include <p4est.h>
#include <p4est_mesh.h>
#include <p8est.h>
#include <p8est_mesh.h>
#include <p8est_iterate.h>


//These three globals values MUST match the corresponding ones
//in the accompanying Fortran module within FEMPAR
const static int FEMPAR_do_nothing_flag =  0;
const static int FEMPAR_refinement_flag =  1;
const static int FEMPAR_coarsening_flag = -1;

static int current_quadrant_index = 0;

void F90_p4est_init_environment();
void F90_p4est_finalize_environment();
void F90_p4est_new_unit_square_connectivity(p4est_connectivity_t **);
void F90_p4est_connectivity_set_bounding_box_limits( p4est_connectivity_t **, const double *);
void F90_p4est_connectivity_destroy(p4est_connectivity_t **);
void F90_p8est_connectivity_destroy(p8est_connectivity_t **);
void F90_p4est_mesh_destroy(p4est_mesh_t **);
void F90_p8est_mesh_destroy(p8est_mesh_t **);
void F90_p4est_ghost_destroy(p4est_ghost_t **);
void F90_p8est_ghost_destroy(p8est_ghost_t **);
void F90_p4est_destroy(p4est_t **);
void F90_p8est_destroy(p8est_t **);
int refine_callback_2d(p4est_t *,p4est_topidx_t, p4est_quadrant_t *);
int refine_callback_3d(p8est_t *,p4est_topidx_t, p8est_quadrant_t *);
void init_fn_callback_2d(p4est_t *,p4est_topidx_t,p4est_quadrant_t *);
void init_fn_callback_3d(p8est_t *,p4est_topidx_t,p8est_quadrant_t *);
void edge_callback(p8est_iter_edge_info_t * info, void * user_data);
int weight_callback_2d(p4est_t *,p4est_topidx_t, p4est_quadrant_t *);
int weight_callback_3d(p8est_t *,p4est_topidx_t, p8est_quadrant_t *);


/* The quad_to_quad_by_edge list stores one value for each local quadrant's edge.
 * This value is in 0..local_num_quadrants-1 for local quadrants, or in
 * local_num_quadrants + (0..ghost_num_quadrants-1) for ghost quadrants.
 * The quad_to_edge list has equally many entries which are either:
 * 1. A value of v = 0..23 indicates one same-size neighbor.
 *    This value is decoded as v = r * 12 + ne, where ne = 0..11 is the
 *    neighbor's connecting edge number and r = 0..1 is the relative
 *    orientation of the neighbor's edge.
 * 2. A value of v = 24..71 indicates a double-size neighbor.
 *    This value is decoded as v = 24 + h * 24 + r * 12 + ne, where
 *    r and nf are as above and h = 0..1 is the number of the subedge.
 * 3. A value of v = -24..-1 indicates two half-size neighbors.
 *    In this case the corresponding quad_to_quad_by_edge index points into the
 *    quad_to_half_by_edge array which stores two quadrant numbers per index,
 *    and the orientation of the smaller edges follows from 24 + v.
 *    The entries of quad_to_half encode between local and ghost quadrant
 *    in the same way as the quad_to_quad values described above.
 * A quadrant on the boundary of the forest sees itself and its face number.*/

typedef struct edge_info
{
  p4est_locidx_t local_num_quadrants; 
  p4est_locidx_t *quad_to_quad_by_edge;
  int8_t         *quad_to_edge;
  p4est_locidx_t *quad_to_half_by_edge; 
  p4est_locidx_t quad_to_half_by_edge_size;
}
edge_info_t;


//void p4_savemesh ( char    filename[],
//                   p8est_t *p4est);
//                   
//void p4est_save_all ( char    filename[],
//                      p8est_t *p4est);

//#ifdef __cplusplus
//#if 0
//{
//#endif
//}
//#endif

#endif
