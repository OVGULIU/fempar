! Copyright (C) 2014 Santiago Badia, Alberto F. Martín and Javier Principe
!
! This file is part of FEMPAR (Finite Element Multiphysics PARallel library)
!
! FEMPAR is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! FEMPAR is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with FEMPAR. If not, see <http://www.gnu.org/licenses/>.
!
! Additional permission under GNU GPL version 3 section 7
!
! If you modify this Program, or any covered work, by linking or combining it 
! with the Intel Math Kernel Library and/or the Watson Sparse Matrix Package 
! and/or the HSL Mathematical Software Library (or a modified version of them), 
! containing parts covered by the terms of their respective licenses, the
! licensors of this Program grant you additional permission to convey the 
! resulting work. 
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
module SB_block_sparse_matrix_array_assembler_names
  use types_names
  use dof_descriptor_names
  use allocatable_array_names

  ! Abstract modules
  use SB_matrix_array_assembler_names
  use matrix_names
  use array_names

  ! Concrete implementations
  use sparse_matrix_names
  use block_sparse_matrix_names
  use serial_block_array_names

  implicit none
# include "debug.i90"
  private

  type, extends(SB_matrix_array_assembler_t) :: SB_block_sparse_matrix_array_assembler_t
contains
  procedure :: assembly         => block_sparse_matrix_array_assembler_assembly
		procedure :: compress_storage => block_sparse_matrix_array_assembler_compress_storage
		procedure :: allocate         => block_sparse_matrix_array_assembler_allocate
end type

! Data types
public :: SB_block_sparse_matrix_array_assembler_t

contains
subroutine block_sparse_matrix_array_assembler_assembly( this, & 
                                                         number_fe_spaces, &
                                                         number_nodes, &
                                                         elem2dof, &
                                                         field_blocks, &
                                                         field_coupling, &
                                                         elmat, &
                                                         elvec )
 implicit none
 class(SB_block_sparse_matrix_array_assembler_t), intent(inout) :: this
 integer(ip)                                    , intent(in)    :: number_fe_spaces
 integer(ip)                                    , intent(in)    :: number_nodes(number_fe_spaces)
 type(i1p_t)                                    , intent(in)    :: elem2dof(number_fe_spaces)
 integer(ip)                                    , intent(in)    :: field_blocks(number_fe_spaces)
 logical                                        , intent(in)    :: field_coupling(number_fe_spaces,number_fe_spaces)
 ! elmat MUST have as many rows/columns as \sum_{i=1}^{number_fe_spaces} number_nodes(i)
 real(rp)                                       , intent(in)    :: elmat(:,:) 
 ! elvec MUST have as many entries as \sum_{i=1}^{number_fe_spaces} number_nodes(i)
 real(rp)                                       , intent(in)    :: elvec(:)  

 class(matrix_t), pointer :: matrix
 class(array_t) , pointer :: array

 matrix => this%get_matrix()
 array  => this%get_array()

 select type(matrix)
    class is(block_sparse_matrix_t)
    call element_block_sparse_matrix_assembly( matrix, & 
																																														 number_fe_spaces, & 
																																														 number_nodes, &
																																														 elem2dof, &
																																														 field_blocks, & 
																																														 field_coupling, &
																																														 elmat )
    class default
    check(.false.)
 end select

 select type(array)
    class is(serial_block_array_t)
    call element_serial_block_array_assembly( array, & 
																																													 number_fe_spaces, & 
																																													 number_nodes, &
																																														elem2dof, &
																																														field_blocks, & 
																																														elvec )
    class default
    check(.false.)
 end select
end subroutine block_sparse_matrix_array_assembler_assembly


subroutine block_sparse_matrix_array_assembler_compress_storage(this,sparse_matrix_storage_format)
  implicit none
  class(SB_block_sparse_matrix_array_assembler_t), intent(inout) :: this
  character(*)                                   , intent(in)    :: sparse_matrix_storage_format
		class(matrix_t), pointer :: matrix
		matrix=>this%get_matrix() 
   select type(matrix)
    class is(block_sparse_matrix_t)
    call matrix%compress_storage(sparse_matrix_storage_format)
    class default
    check(.false.)
 end select
end subroutine block_sparse_matrix_array_assembler_compress_storage

subroutine block_sparse_matrix_array_assembler_allocate(this)
  implicit none
  class(SB_block_sparse_matrix_array_assembler_t), intent(inout) :: this
		class(array_t), pointer :: array
  array=>this%get_array()
  call array%allocate()
end subroutine block_sparse_matrix_array_assembler_allocate

subroutine element_block_sparse_matrix_assembly( matrix, & 
                                                 number_fe_spaces, &
                                                 number_nodes, &
                                                 elem2dof, &
                                                 field_blocks, &
                                                 field_coupling, &
                                                 elmat )
  implicit none
  ! Parameters
  type(block_sparse_matrix_t), intent(inout) :: matrix
  integer(ip)                , intent(in)    :: number_fe_spaces
  integer(ip)                , intent(in)    :: number_nodes(number_fe_spaces)
  type(i1p_t)                , intent(in)    :: elem2dof(number_fe_spaces)
  integer(ip)                , intent(in)    :: field_blocks(number_fe_spaces) 
  logical                    , intent(in)    :: field_coupling(number_fe_spaces,number_fe_spaces)
  real(rp)                   , intent(in)    :: elmat(:,:) 
  
  integer(ip) :: ielmat, ife_space, iblock, inode, idof
  integer(ip) :: jelmat, jfe_space, jblock, jnode, jdof
  type(sparse_matrix_t), pointer :: mat  
  
  !ielmat = 0
  !do ife_space = 1, number_fe_spaces
  !   iblock = field_blocks(ife_space)
  !   do inode = 1, number_nodes(ife_space)
  !      idof = elem2dof(ife_space)%p(inode)
  !      ielmat = ielmat + 1
  !      jelmat = 0
  !      do jfe_space = 1, number_fe_spaces
  !         jblock = field_blocks(jfe_space)
  !         if ( field_coupling(ife_space,jfe_space) ) then
  !             mat => matrix%get_block(iblock,jblock)
  !             do jnode = 1, number_nodes(jfe_space)
  !                jdof = elem2dof(jfe_space)%p(jnode)
  !                jelmat = jelmat + 1
  !                call mat%insert(idof,jdof,elmat(ielmat,jelmat),1,mat%get_num_rows(),1,mat%get_num_cols())
  !             end do
  !         else
  !             jelmat = jelmat + number_nodes(jfe_space)
  !         end if
  !      end do
  !   end do
  !end do
  
 ielmat=0
 do ife_space=1, number_fe_spaces
   iblock = field_blocks(ife_space)
   jelmat=0
   do jfe_space=1, number_fe_spaces
     jblock = field_blocks(jfe_space)
     if ((field_coupling(ife_space,jfe_space))) then
         mat => matrix%get_block(iblock,jblock)
         call mat%insert(number_nodes(ife_space), &
                         number_nodes(jfe_space), &
                         elem2dof(ife_space)%p, &
                         elem2dof(jfe_space)%p, &
                         ielmat, &
                         jelmat, &
                         elmat)
     end if
     jelmat=jelmat+number_nodes(jfe_space)
   end do
   ielmat=ielmat+number_nodes(ife_space)
 end do
end subroutine element_block_sparse_matrix_assembly

subroutine element_serial_block_array_assembly( array, &
                                                number_fe_spaces, &
                                                number_nodes, &
                                                elem2dof, &
                                                field_blocks, &
                                                elvec )
  implicit none
  ! Parameters
  type(serial_block_array_t), intent(inout) :: array
  integer(ip)               , intent(in)    :: number_fe_spaces
  integer(ip)               , intent(in)    :: number_nodes(number_fe_spaces)
  type(i1p_t)               , intent(in)    :: elem2dof(number_fe_spaces)
  integer(ip)               , intent(in)    :: field_blocks(number_fe_spaces)
  real(rp)                  , intent(in)    :: elvec(:)
  
  integer(ip) :: ielmat, ife_space, iblock, inode, idof

  ielmat = 0
  do ife_space = 1, number_fe_spaces
     iblock = field_blocks(ife_space)
     do inode = 1, number_nodes(ife_space)
        idof = elem2dof(ife_space)%p(inode) 
        ielmat = ielmat+1
        if ( idof  > 0 ) then
           array%blocks(iblock)%b(idof) =  array%blocks(iblock)%b(idof) + elvec(ielmat)
        end if
     end do
  end do

end subroutine element_serial_block_array_assembly

end module SB_block_sparse_matrix_array_assembler_names
