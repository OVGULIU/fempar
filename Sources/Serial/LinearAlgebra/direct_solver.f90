module direct_solver_names
    ! Serial modules
    USE types_names
    USE memor_names
    USE base_direct_solver_names
    USE pardiso_mkl_direct_solver_names
    USE umfpack_direct_solver_names
    USE sparse_matrix_names, only: sparse_matrix_t
    USE serial_scalar_array_names
    USE FPL

implicit none
# include "debug.i90"

    ! Parameter strings to be used in the Parameter List
    character(len=*), parameter :: direct_solver_type = 'direct_solver_name'

    type :: direct_solver_t
    private
        class(base_direct_solver_t), pointer :: base_direct_solver => NULL()
    contains
    private
        procedure, non_overridable, public :: set_type                     => direct_solver_set_type
        procedure, non_overridable, public :: set_defaults                 => direct_solver_set_defaults
        procedure, non_overridable, public :: set_type_from_pl             => direct_solver_set_type_from_pl
        procedure, non_overridable, public :: set_parameters_from_pl       => direct_solver_set_parameters_from_pl
        procedure, non_overridable, public :: set_matrix                   => direct_solver_set_matrix
        procedure, non_overridable, public :: symbolic_setup               => direct_solver_symbolic_setup
        procedure, non_overridable, public :: numerical_setup              => direct_solver_numerical_setup
        procedure, non_overridable, public :: log_info                     => direct_solver_log_info
        procedure, non_overridable, public :: solve                        => direct_solver_solve
        procedure, non_overridable, public :: free                         => direct_solver_free
    end type

contains

    subroutine direct_solver_set_type(this, name)
    !-----------------------------------------------------------------
    !< Allocate the concrete direct solver from a given solver name
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
        character(len=*),       intent(in)    :: name
    !-----------------------------------------------------------------
        if(associated(this%base_direct_solver)) then
            call this%base_direct_solver%free_clean()
            deallocate(this%base_direct_solver)
        endif

        select case (name)
            case (pardiso_mkl_name)
                this%base_direct_solver => create_pardiso_mkl_direct_solver()
            case (umfpack_name)
                this%base_direct_solver => create_umfpack_direct_solver()
        end select
    end subroutine direct_solver_set_type


    subroutine direct_solver_set_type_from_pl(this, parameter_list)
    !-----------------------------------------------------------------
    !< Allocate the concrete direct solver from a solver name stored 
    !< in the parameter list
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
        type(ParameterList_t),  intent(in)    :: parameter_list
        character(len=:), allocatable         :: name
        integer(I4P)                          :: DataSizeInBytes
        integer                               :: FPLError
#ifdef DEBUG
        logical                               :: is_present
        logical                               :: is_string
        integer(ip), allocatable              :: shape(:)
    !-----------------------------------------------------------------
        is_present = parameter_list%isPresent(Key=direct_solver_type)
        is_string = parameter_list%isOfDataType(Key=direct_solver_type, mold='string')
        shape = parameter_list%getshape(Key=direct_solver_type)
        ! check if direct_solver_type is present and is a scalar string
        ! in the given parameter list,
        assert(is_present .and. is_string .and. size(shape) == 0) 
#endif
        DataSizeInBytes = parameter_list%DataSizeInBytes(Key=direct_solver_type)
        allocate(character(len=DataSizeInBytes) :: name, stat=FPLError)
        assert(FPLError == 0)
        FPLError = parameter_list%Get(Key=direct_solver_type, Value=name)
        assert(FPLError == 0)
        call this%set_type(name)
    end subroutine direct_solver_set_type_from_pl


    subroutine direct_solver_set_defaults(this)
    !-----------------------------------------------------------------
    !< Set the default parameter of the concrete direct solver
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%set_defaults()
    end subroutine direct_solver_set_defaults


    subroutine direct_solver_set_parameters_from_pl(this, parameter_list)
    !-----------------------------------------------------------------
    !< Set parameters from values stored in a given parameter list
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
        type(ParameterList_t),  intent(in)    :: parameter_list
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%set_parameters_from_pl(parameter_list)
    end subroutine direct_solver_set_parameters_from_pl



    subroutine direct_solver_set_matrix(this, matrix)
    !-----------------------------------------------------------------
    !< Associate the concrete direct solver with a matrix
    !-----------------------------------------------------------------
        class(direct_solver_t),        intent(inout) :: this
        type(sparse_matrix_t), target, intent(in)    :: matrix
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%set_matrix(matrix)
    end subroutine direct_solver_set_matrix


    subroutine direct_solver_symbolic_setup(this)
    !-----------------------------------------------------------------
    !< Concrete direct solver performs analysis phase
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%symbolic_setup()
    end subroutine direct_solver_symbolic_setup


    subroutine direct_solver_numerical_setup(this)
    !-----------------------------------------------------------------
    !< Concrete direct solver performs factorization phase
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%numerical_setup()
    end subroutine direct_solver_numerical_setup


    subroutine direct_solver_log_info(this)
    !-----------------------------------------------------------------
    !< Print direct solver log info
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%log_info()
    end subroutine direct_solver_log_info


    subroutine direct_solver_solve(this, x, y)
    !-----------------------------------------------------------------
    !< Computes y <- A^-1 * x
    !-----------------------------------------------------------------
        class(direct_solver_t),       intent(inout) :: this
        class(serial_scalar_array_t), intent(in)    :: x
        class(serial_scalar_array_t), intent(inout) :: y
    !-----------------------------------------------------------------
        assert(associated(this%base_direct_solver))
        call this%base_direct_solver%solve(x,y)
    end subroutine direct_solver_solve


    subroutine direct_solver_free(this, action)
    !-----------------------------------------------------------------
    !< Computes y <- A^-1 * x
    !-----------------------------------------------------------------
        class(direct_solver_t), intent(inout) :: this
        integer(ip), optional,  intent(in)    :: action
    !-----------------------------------------------------------------
        if(associated(this%base_direct_solver)) then
            if(present(action)) then
                select case (action)
                    case (free_numerical_setup)
                        call this%base_direct_solver%free_numerical()
                    case (free_symbolic_setup)
                        call this%base_direct_solver%free_symbolic()
                    case (free_clean)
                        call this%base_direct_solver%free_clean()
                    case DEFAULT
                        call this%base_direct_solver%free_clean()                
                end select
            else
                call this%base_direct_solver%free_clean()                
            endif
            deallocate(this%base_direct_solver)
        endif
        nullify(this%base_direct_solver)
    end subroutine direct_solver_free

end module direct_solver_names
