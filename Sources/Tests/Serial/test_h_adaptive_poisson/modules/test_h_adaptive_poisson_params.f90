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
module test_h_adaptive_poisson_params_names
  use fempar_names
# include "debug.i90"

  implicit none
  private

  character(len=*), parameter :: fe_formulation_key            = 'fe_formulation'
  character(len=*), parameter :: laplacian_type_key            = 'laplacian_type'
  character(len=*), parameter :: reference_fe_order_key        = 'reference_fe_order'    
  character(len=*), parameter :: write_solution_key            = 'write_solution'        
  character(len=*), parameter :: use_void_fes_key              = 'use_void_fes'
  character(len=*), parameter :: use_void_fes_case_key         = 'use_void_fes_case'

  type :: test_poisson_params_t  
   contains
     procedure, non_overridable             :: process_parameters
     procedure, non_overridable             :: get_parameter_list
     procedure, non_overridable             :: get_fe_formulation
     procedure, non_overridable             :: get_reference_fe_order
     procedure, non_overridable             :: get_write_solution
     procedure, non_overridable             :: get_laplacian_type
     procedure, non_overridable             :: get_use_void_fes
     procedure, non_overridable             :: get_use_void_fes_case
  end type test_poisson_params_t  

  ! Types
  public :: test_poisson_params_t

contains
  
  !==================================================================================================
  subroutine test_poisson_define_user_parameters()
    implicit none

    ! IO parameters
    call parameter_handler%add(fe_formulation_key, '--fe-formulation', 'cG', 'cG or dG FE formulation for Poisson problem (cG,dG)', switch_ab='-f')
    call parameter_handler%add(reference_fe_order_key, '--reference-fe-order', 1, 'Order of the fe space reference fe', switch_ab='-order') 
    call parameter_handler%add(write_solution_key, '--write-solution', .false., 'Write solution in VTK format', switch_ab='-wsolution') 
    call parameter_handler%add(laplacian_type_key, '--laplacian-type', 'scalar', 'Scalar or Vector-Valued Laplacian PDE? (scalar,vector)', switch_ab='-lt') 
    
    call parameter_handler%add(use_void_fes_key, '--use-void-fes', .false., 'Use a hybrid FE space formed by full and void FEs', switch_ab='-use-voids') 
    call parameter_handler%add(use_void_fes_case_key, '--use-void-fes-case', 'popcorn', &
                'Select where to put void fes using one of the predefined patterns. Possible values: `popcorn`, `half`, `quarter`', &
                switch_ab='-use-voids-case')  
  end subroutine test_poisson_define_user_parameters
 
  !==================================================================================================

  subroutine process_parameters(this)
    implicit none
    class(test_poisson_params_t) , intent(in)  :: this
    call parameter_handler%process_parameters(test_poisson_define_user_parameters)
  end subroutine process_parameters

  !==================================================================================================

  function get_parameter_list(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    type(ParameterList_t), pointer            :: get_parameter_list
    get_parameter_list  => parameter_handler%get_values()
  end function get_parameter_list

  ! GETTERS *****************************************************************************************
  !==================================================================================================
  function get_fe_formulation(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    character(len=:), allocatable             :: get_fe_formulation
    call parameter_handler%GetAsString(key = fe_formulation_key, string = get_fe_formulation)
  end function get_fe_formulation
    
  !==================================================================================================
  function get_reference_fe_order(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    integer(ip)                               :: get_reference_fe_order
    call parameter_handler%Get(key = reference_fe_order_key, Value = get_reference_fe_order)
  end function get_reference_fe_order
  
  !==================================================================================================
  function get_write_solution(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    logical                                   :: get_write_solution
    call parameter_handler%Get(key = write_solution_key, Value = get_write_solution)
  end function get_write_solution
  
  !==================================================================================================
  function get_laplacian_type(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    character(len=:), allocatable             :: get_laplacian_type
    call parameter_handler%GetAsString(key = laplacian_type_key, string = get_laplacian_type)
  end function get_laplacian_type 

  !==================================================================================================
  function get_use_void_fes(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    logical                                   :: get_use_void_fes
    call parameter_handler%Get(key = use_void_fes_key, value = get_use_void_fes)
  end function get_use_void_fes

  !==================================================================================================
  function get_use_void_fes_case(this)
    implicit none
    class(test_poisson_params_t) , intent(in) :: this
    character(len=:), allocatable             :: get_use_void_fes_case
    call parameter_handler%GetAsString(key = use_void_fes_case_key, string = get_use_void_fes_case)
  end function get_use_void_fes_case

end module test_h_adaptive_poisson_params_names
