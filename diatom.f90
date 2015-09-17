module diatom_module
  !
  use accuracy
  use timer
  use functions, only : analytical_fieldT
  use symmetry, only   : sym,SymmetryInitialize
  !
  implicit none
  !                     by Lorenzo Lodi
  !                     Specifies variables needed for storing a temporary (scratch) copy
  !                     of the input (useful for jumping around).
  !
  integer             :: ierr
  character(len=wl)   :: line_buffer
  integer,parameter   :: max_input_lines=500000  ! maximum length (in lines) of input. 500,000 lines is plenty..
  !                                              ! to avoid feeding in GB of data by mistake.
  !
  ! main method used for solving the J=0 problem, i.e. to solve the one-dimentional Schrodinger equation.
  character(len=wl)   :: solution_method = "5POINTDIFFERENCES"  ! kinetic energy approximated by 5-point finite-diff. formula
  !
  ! Type to describe different terms from the hamiltonian, e.g. potential energy, spin-orbit, <L^2>, <Lx>, <Ly> functions.
  !
  integer(ik),parameter   :: verbose=5
  integer(ik),parameter   :: Nobjects = 15  ! number of different terms of the Hamiltonian 
  !                                          (poten,spinorbit,L2,LxLy,spinspin,spinspino,bobrot,spinrot,diabatic,lambda-opq,lambda-p2q)
  !
  ! In order to add a new field:
  ! 1. Change Nobjects
  ! 2. Add the name of the field to the CASE line where all fields are listed: case("SPIN-ORBIT","SPIN-ORBIT-X"....
  ! 3. Add the CASE-section describing the input of the new field 
  ! 4. Add a similar CASE-section describing the input of the new field to the CASE("ABINITIO") part
  ! 5. Introduce a new name for the new field (object). 
  ! 6. Define new array in type(fieldT),pointer .....
  ! 7. Add a new case to all cases where the fieds appear: at the end of the input subroutine, 
  !    two times in in map_fields_onto_grid, in duo_j0, in sf_fitting
  ! 8. Add corresposponding check_and_print_coupling in map_fields_onto_grid
  ! 9. Add the corresponding name of the field to  "use diatom_module,only" in "refinement"
  !
  ! Current list of fields:
  ! 
  !        case (1) poten(iterm)
  !        case (2) spinorbit(iterm)
  !        case (3) l2(iterm)
  !        case (4) lxly(iterm)
  !        case (5) spinspin(iterm)
  !        case (6) spinspino(iterm)
  !        case (7) bobrot(iterm)
  !        case (8) spinrot(iterm)
  !        case (9) diabatic(iterm)
  !        case (10) lambdaopq(iterm)
  !        case (11) lambdap2q(iterm)
  !        case (12) lambdaq(iterm)
  !        case(Nobjects-2) abinitio(iterm)
  !        case(Nobjects-1) brot(iterm)
  !        case(Nobjects) dipoletm(iterm)
  !
  !
  character(len=wl),parameter :: CLASSNAMES(1:Nobjects)  = (/"POTEN","SPINORBIT","L2","L+","SPIN-SPIN","SPIN-SPIN-O",&
                                                             "BOBROT","SPIN-ROT","DIABATIC","LAMBDAOPQ","LAMBDAP2Q","LAMBDAQ",&
                                                             "ABINITIO","BROT","DIPOLE"/)
  !
  type symmetryT
    !
    integer(ik) :: gu = 0
    integer(ik) :: pm = 0
    !
  end type symmetryT
  !
  ! type describing the parameter geneology
  !
  type linkT
    !
    integer(ik) :: iobject
    integer(ik) :: ifield
    integer(ik) :: iparam
    !
  end type linkT
  !
  type braketT
    integer(ik) :: ilambda = 0.0_rk
    integer(ik) :: jlambda = 0.0_rk
    real(rk) :: sigmai = 0.0_rk
    real(rk) :: sigmaj = 0.0_rk
    real(rk) :: value = 0.0_rk
  end type braketT
  !
  ! files with the eigenvectors 
  !
  type  eigenfileT
    !
    character(len=cl)  :: dscr       ! file with fingeprints and descriptions of each levels + energy values
    character(len=cl)  :: primitives ! file with the primitive quantum numbres   
    character(len=cl)  :: vectors    ! eigenvectors stored here 
    !
  end type  eigenfileT 
  !
  type fieldT
    !
    character(len=cl)    :: name         ! Identifying name of the  function
    character(len=cl)    :: type='NONE'  ! Identifying type of the function
    character(len=cl)    :: class='NONE' ! Identifying class of the function (poten, spinorbit,dipole,abinitio etc)
    !
    ! variable used for GRID curves to specify interpolation and extrapolation  options
    ! 
    ! character(len=cl)    :: interpolation_type='CUBICSPLINES'
    !
    character(len=cl)    :: interpolation_type='QUINTICSPLINES'
    !
    integer(ik)          :: iref         ! reference number of the term as given in input (bra in case of the coupling)
    integer(ik)          :: jref         ! reference number of the coupling term as given in input (ket in case of the coupling)
    integer(ik)          :: istate       ! the actual state number (bra in case of the coupling)
    integer(ik)          :: jstate       ! the actual state number (ket in case of the coupling)
    integer(ik)          :: Nterms       ! Number of terms or grid points
    integer(ik)          :: Lambda       ! identification of the electronic state Lambda
    integer(ik)          :: Lambdaj      ! identification of the electronic state Lambda (ket)
    integer(ik)          :: omega        ! identification of the electronic state omega
    integer(ik)          :: multi        ! identification of the electronic spin (bra for the coupling)
    integer(ik)          :: jmulti       ! identification of the ket-multiplicity
    real(rk)             :: sigmai       ! the bra-projection of the spin
    real(rk)             :: sigmaj       ! the ket-projection of the spin
    real(rk)             :: spini        ! electronic spin (bra component for couplings)
    real(rk)             :: spinj        ! electronic spin of the ket vector for couplings
    complex(rk)          :: complex_f=(1._rk,0._rk)  ! defines if the term is imaginary or real
    real(rk)             :: factor=1.0_rk      ! defines if the term is imaginary or real
    real(rk)             :: fit_factor=1.0     ! defines if the term is imaginary or real
    real(rk),pointer     :: value(:)     ! Expansion parameter or grid values from the input
    type(symmetryT)      :: parity       ! parity of the electronic state as defined by the molecular inversion (g,u), 
     !                                        or laboratory inversion (+,-)
    real(rk),pointer     :: gridvalue(:) ! Expansion parameter or a grid value on the grid used inside the program
    real(rk),pointer     :: weight(:)    ! fit (1) or no fit (0)
    real(rk),pointer     :: grid(:)      ! grid value
    real(rk),pointer     :: matelem(:,:) ! matrix elements
    real(rk)             :: refvalue = 0 ! reference value will be used as a shift to be applied to the ab initio function used 
    !                                         for the fitting constraints
    character(len=cl),pointer :: forcename(:) ! The parameter name
    integer(ik)          :: nbrakets=0   ! total number of different combinations of lambda and sigma in matrix elements (maximum 4)
    type(braketT)        :: braket(4)   ! here all possible combinations of values <+/-lambda,+/-sigma|A|+/-lambdaj,+/-sigma> 
    !                                                                                                                  can be listed
    procedure (analytical_fieldT),pointer, nopass :: analytical_field => null()
    type(linkT),pointer   :: link(:)       ! address to link with the fitting parameter in a different object in the fit
    logical               :: morphing = .false.    ! When morphing is the field is used to morph the ab initio couterpart
    !                                                towards the final object
    logical               :: molpro = .false.      ! The object is given in the molpro representaion (|x> and |y>) 
    integer(ik)           :: ix_lz_y = 0           ! The value of the matrix element (-I)<x|Lz|y> for i-state
    integer(ik)           :: jx_lz_y = 0           ! The value of the matrix element (-I)<x|Lz|y> for j-state
    !
  end type fieldT
  !
  type jobT
      logical             :: select_gamma(4) ! the diagonalization will be done only for selected gamma's
      integer(ik)         :: nroots(4)=1e8   ! number of the roots to be found in variational diagonalization with syevr
      integer(ik)         :: maxiter = 1000  ! maximal number of iterations in arpack
      real(rk)            :: tolerance = 0     ! tolerance for arpack diagonalization, 0 means the machine accuracy
      real(rk)            :: upper_ener = 1e9  ! upper energy limit for the eigenvalues found by diagonalization with syevr
      real(rk)            :: thresh = -1e-18   ! thresh of general use
      real(rk)            :: zpe         ! zero-point-energy
      character(len=cl)   :: diagonalizer = 'SYEV'
      character(len=cl)   :: molecule = 'H2'
      character(len=cl)   :: contraction = 'VIB' ! contraction
      real(rk)            :: vibenermax = 1e9    !     contraction parameter: energy
      integer(ik),pointer :: vibmax(:)           !     contraction parameter: vibration quantum
      real(rk)            :: potmin      ! absolute minimum of the ground PEC
      integer(ik)         :: total_parameters =0  !  total number of parameters used to define different hamiltonian fields
      real(rk)            :: degen_threshold = 1e-6
      real(rk),pointer    :: j_list(:)     ! J values processed
      integer(ik)         :: nJ = 1        ! Number of J values processed 
      character(len=cl)   :: IO_eigen = 'NONE'   ! we can either SAVE to or READ from the eigenfunctions from an external file
      character(len=cl)   :: IO_dipole = 'NONE'  ! we can either SAVE to or READ from an external file the dipole moment 
      !                                                matrix elements on the contr. basis 
      type(eigenfileT)    :: eigenfile
      character(len=cl)   :: symmetry = 'CS(M)'    ! molecular symmetry
      real(rk)   :: diag_L2_fact = 1._rk    ! specifies the convention used for the diagonal contribution
                                            !  due to L^2 = LxLx+LyLy+LzLz
      logical,pointer     :: isym_do(:)     ! process or not the symmetry in question
      logical             :: intensity      ! switch on the intensity calculations
      !
  end type jobT
  !
  type gridT
      integer(ik)   :: npoints = 1000       ! grid size
      real(rk)      :: rmin = 1.0,rmax=3.00 ! range of the grid
      real(rk)      :: step = 1e-3          ! step size
      real(rk)      :: alpha = 5.0          ! grid parameter
      real(rk)      :: re = 5.0             ! grid parameter
      integer(ik)   :: nsub = 0             ! grid type parameter (0=uniformly spaced)
      real(rk),pointer :: r(:)              ! the molecular geometry at the grid point
  end type gridT

  type quantaT
    real(rk)     :: Jrot       ! J - real
    integer(ik)  :: irot       ! index of the J value in J_list
    integer(ik)  :: istate     ! e-state
    integer(ik)  :: imulti     ! imulti = 1,..,multiplicity
    real(rk)     :: sigma      ! spin-projection = -spin,-spin+1,..,spin-1,spin
    real(rk)     :: omega      ! sigma+lambda
    real(rk)     :: spin       ! spin
    integer(ik)  :: ilambda    ! ilambda
    integer(ik)  :: v  = 0     ! vibrational quantum
    integer(ik)  :: ivib = 1   ! vibrational quantum number counting all vib-contracted states
    integer(ik)  :: ilevel = 1  ! primitive quantum
    integer(ik)  :: iroot       ! running number
    integer(ik)  :: iparity = 0
    integer(ik)  :: igamma = 1
    character(len=cl) :: name         ! Identifying name of the  function
  end type quantaT
  !
  type eigenT
      real(rk),pointer :: vect(:,:)      ! the eigenvector in the J=0 contracted representaion
      real(rk),pointer :: val(:)         ! the eigenvalue
      type(quantaT),pointer ::quanta(:)  ! the quantum numbers
      integer(ik)      :: Nlevels
      integer(ik)      :: Ndimen
  end type eigenT
  !
  type basisT
      type(quantaT),pointer :: icontr(:)  ! the quantum numbers
      integer(ik)           :: Ndimen
  end type basisT
  !
  type actionT
     !
     logical :: fitting       = .false.
     logical :: intensity     = .false.
     logical :: frequency     = .false.
     logical :: matelem       = .false.
     !
  end type actionT
  !
  type obsT
     !
     real(rk)      :: Jrot
     real(rk)      :: Jrot_      ! J - real (lower)
     integer(ik)   :: irot       ! index of the J value in J_list
     integer(ik)   :: irot_
     integer(ik)   :: symmetry
     integer(ik)   :: N
     integer(ik)   :: N_         ! N lower
     integer(ik)   :: iparity
     integer(ik)   :: iparity_   ! parity +/- (0,1) of the lower state lower
     real(rk)      :: energy
     real(rk)      :: frequency
     real(rk)      :: weight
     type(quantaT) :: quanta
     type(quantaT) :: quanta_  ! quantum numbers of the lower state
     !
  end type obsT
  type thresholdsT
     real(rk) :: intensity    = -1e0    ! threshold defining the output intensities
     real(rk) :: linestrength = -1e0    ! threshold defining the output linestrength
     real(rk) :: coeff        = -1e0    ! threshold defining the eigenfunction coefficients
                                        ! taken into account in the matrix elements evaluation.
  end type thresholdsT


  type IntensityT
     logical             :: do = .false.     ! process (.true.) or not (.false.) the intensity (or TM) calculations 
     character(cl)       :: action           ! type of the intensity calculations:
                                             ! absorption, emission, tm (transition moments),
                                             !  raman, and so on. 
     real(rk)            :: temperature      ! temperature in K
     real(rk)            :: part_func        ! partition function 
     real(rk)            :: ZPE              ! zero point energy
     type(thresholdsT)   :: threshold        ! different thresholds
     real(rk),pointer    :: gns(:)           ! nuclear stat. weights
     integer(ik),pointer :: isym_pairs(:)    ! numbers defining symmetry pairs with allowed transitions, analogous to gns
     real(rk)            :: freq_window(1:2) ! frequency window (1/cm)
     real(rk)            :: erange_low(1:2)  ! energy range for the lower state
     real(rk)            :: erange_upp(1:2)  ! energy range for the upper state
     real(rk)            :: J(1:2)           ! range of J-values, from..to; in order to avoid double counting of transitions
                                             ! in the calculations it is always assumed that 
                                             ! J1<=J_lower<=J2 and J1<=J_upper<J2;
                                             !
     type(quantaT) :: lower                   ! lower state range of the quantun numbers employed 
     type(quantaT) :: upper                   ! upper state range of the quantun numbers employed 
                                             ! in intensity calculations; (imode,1:2), 
                                             ! where 1 stands for the beginning and 2 for the end. 
     !
     integer(ik)         :: swap_size    = 0 ! the number of vectors to keep in memory
     character(cl)       :: swap = "NONE"    ! whether save the compacted vectors or read
     character(cl)       :: swap_file  ="compress"   ! where swap the compacted eigenvectors to
     character(cl)       :: linelist_file="NONE"   ! filename for the line list (filename.states and filename.trans)
     integer(ik)         :: int_increm = 1e9 ! used to print out the lower energies needed to select int_increm intensities
     real(rk)            :: factor = 1.0d0   ! factor <1 to be applied the maxsize of the vector adn thus to be shrunk 
     logical             :: matelem =.false.  ! switch for the line-strenth-type matelems  (matrix elements of the dipole moment)
     !
 end type IntensityT
  !
  type matrixT
     !
     real(rk),pointer    :: matrix(:,:)
     integer(ik),pointer :: irec(:)
     !
  end type matrixT
  !
  type fittingT
     !
     logical              :: run
     integer(ik)          :: nJ = 1        ! Number of J values processed 
     real(rk),pointer     :: j_list(:)     ! J-values processed in the fit
     integer(ik)          :: iparam(1:2) = (/1,100000/)
     integer(ik)          :: itermax = 500
     integer(ik)          :: Nenergies = 1
     integer(ik)          :: parmax =0          ! total number of all parameters used
     real(rk)             :: factor = 1.0_rk
     real(rk)             :: target_rms = 1e-8
     real(rk)             :: robust = 0
     character(len=cl)    :: geom_file = 'pot.fit'
     character(len=cl)    :: output_file = 'fitting'
     character(len=cl)    :: fit_type = 'LINUR'      ! to switch between fitting methods.
     real(rk)             :: threshold_coeff    = -1e-18
     real(rk)             :: threshold_lock     = -1e-18
     type(obsT),pointer   :: obs(:)           ! experimental data
     !
     !type(paramT),pointer :: param(:)         ! fitting parameters
     !
  end type fittingT
  !
  type fieldmapT
    integer(ik)          :: Nfields
  end type fieldmapT
  !
  integer, parameter :: trk        = selected_real_kind(12)
  integer,parameter  :: jlist_max = 500
  type(fieldT),pointer :: poten(:),spinorbit(:),l2(:),lxly(:),abinitio(:),dipoletm(:),&
                          spinspin(:),spinspino(:),bobrot(:),spinrot(:),diabatic(:),lambdaopq(:),lambdap2q(:),lambdaq(:)
  type(fieldT),pointer :: brot(:)
  type(jobT)   :: job
  type(gridT)  :: grid
  type(quantaT),allocatable :: quanta(:)
  integer(ik),allocatable   :: iquanta2ilevel(:,:,:)
  real(rk),allocatable      :: r(:), d2dr(:), r2sc(:),z(:)
  type(actionT)             :: action   ! defines different actions to perform
  type(fittingT)            :: fitting
  type(IntensityT)            :: Intensity
  !type(symmetryT)             :: sym
  !
  integer(ik)   :: nestates,Nspinorbits,Ndipoles,Nlxly,Nl2,Nabi,Ntotalfields=0,Nss,Nsso,Nbobrot,Nsr,Ndiabatic,&
                   Nlambdaopq,Nlambdap2q,Nlambdaq,vmax
  real(rk)      :: m1,m2,jmin,jmax,amass,hstep
  !type(fieldT),pointer :: refined(:)
  type(fieldmapT) :: fieldmap(Nobjects)
  type(eigenT),allocatable :: eigen(:,:)
  !
  type(basisT),allocatable :: basis(:)
  !
  logical :: gridvalue_allocated  = .false.
  !
  public ReadInput,poten,spinorbit,l2,lxly,abinitio,brot,map_fields_onto_grid,fitting,&
         jmin,jmax,vmax,fieldmap,Intensity,eigen,basis,Ndipoles,dipoletm,linkT,three_j
  save grid, Intensity, fitting, action, job, gridvalue_allocated
  !
  contains
  !
  subroutine ReadInput
    !
    use  input
    !
    integer(ik)  :: iobject(Nobjects)
    integer(ik)  :: ipot=0,iso=0,ncouples=0,il2=0,ilxly=0,iabi=0,idip=0,iss=0,isso=0,ibobrot=0,isr=0,idiab=0
    integer(ik)  :: Nparam,alloc,iparam,i,j,iobs,i_t,iref,jref,istate,jstate,istate_,jstate_,item_,ibraket,iabi_,iterm,iobj
    integer(ik)  :: Nparam_check    !number of parameters as determined automatically by duo (Nparam is specified in input).
    logical      :: zNparam_defined ! true if Nparam is in the input, false otherwise..
    integer(ik)  :: itau,lambda_,x_lz_y_
    logical      :: integer_spin = .false., matchfound
    real(rk)     :: unit_field = 1.0_rk,unit_r = 1.0_rk,spin_,jrot2
    real(rk)     :: f_t,jrot,j_list_(1:jlist_max),omega_,sigma_
    !
    character(len=cl) :: w,ioname
    character(len=wl) :: large_fmt
    !
    integer(ik)       :: iut !  iut is a unit number. 
    !
    type(fieldT),pointer      :: field
    logical :: eof,include_state,allgrids
    logical :: symmetry_defined=.false.
    !
    ! -----------------------------------------------------------
    !
    write(out,"('Read the input')")
    !
    call input_options(echo_lines=.true.,error_flag=1)
    !
    !
    ! default constants
    !
    jmin = 0 ; jmax = 0
    !
    ! To count objects 
    iobject = 0 
    !
    ! read the general input
    ! by Lorenzo Lodi
    ! read everything from std input and write to a temporary (scratch) file.
    !
    write(ioname, '(a, i4)') 'write to a temporary (scratch) file.'
    call IOstart(trim(ioname), iut)
    !
    open(unit=iut, status='scratch', action='readwrite')
    write(large_fmt, '(A,i0,A)') '(A', wl, ')'
    trans_loop: do i=1, max_input_lines
      read(unit=*,fmt=large_fmt,iostat=ierr) line_buffer
      if(ierr /=0) exit trans_loop
      write(iut, '(a)') trim(line_buffer)
    enddo trans_loop
    rewind(iut)
    !
    do
        zNparam_defined = .false. ! For each input block, set number of points/params to undefined
        call read_line(eof,iut) ; if (eof) exit
        call readu(w)
        select case(w)
        !
        case("STOP","FINISH","END")
          exit
        case("")
          print "(1x)"    !  Echo blank lines
          !
          case ("SOLUTIONMETHOD")
          call readu(w)
          solution_method = trim(w)
          ! 
        case ("L2CONVENTION")
          !
          call readu(w)
          !
          select case(w)
             case ("SPECIFY_L^2","SPECIFY_L**2" ,"DEFAULT")
                job%diag_L2_fact = 1._rk  !default case
             case ("SPECIFY_LX^2_PLUS_LY^2", "SPECIFY_LX**2_PLUS_LY**2" )
                job%diag_L2_fact = 0._rk  !Lorenzo's choice
             case default
               call report ("Unrecognized L2CONVENTION "//trim(w)// ". " // &
                           "Implemented: DEFAULT, SPECIFY_L**2, SPECIFY_L^2, SPECIFY_LX^2_PLUS_LY^2" // &
                            ", SPECIFY_LX**2_PLUS_LY**2")
          end select
          !
        case ("MASSES","MASS")
          !
          call readf(m1)
          call readf(m2)
          !
        case ("MOLECULE","MOL")
          !
          call readu(w)
          !
          select case(w)
          !
          case ("C2","ALO","X2","XY","CO","CAO","NIH","MGH")
            !
            job%molecule = trim(w)
            !
          case default
            !
            write (out,"('  I see this molecule for the first time.')")
            !
            !call report ("Unrecognized unit name "//trim(w)//"implemented: (C2,ALO,X2, XY)",.true.)
            !
          end select
          !
        case('J_LIST','JLIST','JROT','J')
          !
          jmin =  1e6
          jmax = -1.0
          integer_spin = .false.
          i = 0
          do while (item<Nitems.and.i<jlist_max)
             !
             i = i + 1
             !
             call readu(w)
             !
             if (trim(w)/="-") then
               !
               read(w,*) jrot
               !
               j_list_(i) = jrot
               !
             else
               !
               call readf(jrot2)
               !
               do while (item<=Nitems.and.nint(2.0*jrot)<nint(2.0*jrot2))
                 !
                 jrot = jrot + 1.0
                 j_list_(i) = jrot
                 i = i + 1
                 !
               enddo
               i = i - 1
               !
             endif
             !
             if (i==1.and.mod(nint(2.0_rk*jrot+1.0_rk),2)==1) integer_spin = .true.
             !
             if (i>1.and.mod(nint(2.0_rk*jrot+1.0_rk),2)==0.and.integer_spin) then
               !
               call report("The multiplicities of jrot in J-list are inconsistent",.true.)
               !
             endif
             !
             jmin = min(jmin,j_list_(i))
             jmax = max(jmax,j_list_(i))
             !
          enddo
          !
          job%nJ = i
          !
          allocate(job%j_list(i),stat=alloc)
          !
          job%J_list(1:i) = J_list_(1:i)
          !
        !case ("JROT")
        !  !
        !  call readf(jmin)
        !  !
        !  if (nitems>2) then
        !    !
        !    call readf(jmax)
        !    !
        !  else
        !    !
        !    jmax = jmin
        !    !
        !  endif
        !  !
        !  ! check the multiplicity
        !  !
        !  if (mod(nint(2.0_rk*jmin+1.0_rk),2)==1) integer_spin = .true.
        !  !
        !  if (mod(nint(2.0_rk*jmax+1.0_rk),2)==0.and.integer_spin) then
        !    !
        !    call report("The multiplicities of jmin and jmax are inconsistent",.true.)
        !    !
        !  endif
        !  !
        case ("NSTATES","NESTATES")
          !
          call readi(nestates)
          !
          if (nestates<1) call report("nestates cannot be 0 or negative",.true.)
          !
          ! the maximum number of couplings possible, assuming each state may be doubly degenerate
          !
          ncouples = 2*nestates*(2*nestates-1)/2
          !
          ! allocate all fields representing the hamiltonian: PEC, spin-orbit, L2, LxLy etc.
          !
          allocate(poten(nestates),spinorbit(ncouples),l2(ncouples),lxly(ncouples),spinspin(nestates),spinspino(nestates), &
                   bobrot(nestates),spinrot(nestates),job%vibmax(nestates),diabatic(ncouples),&
                   lambdaopq(nestates),lambdap2q(nestates),lambdaq(nestates),stat=alloc)
          !
          ! initializing the fields
          !
          job%vibmax = 1e8
          !
          allocate(abinitio(nestates*Nobjects+4*ncouples),stat=alloc)
          !
       case ("GRID")
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
             !
           case ("NPOINTS")
             !
             call readi(grid%npoints)
             !
           case ("NSUB","TYPE")
             !
             call readi(grid%nsub)
             !
           case ("RE","REF")
             !
             call readf(grid%re)
             !
           case ("ALPHA")
             !
             call readf(grid%alpha)
             !
           case("RANGE")
             !
             call readf(grid%rmin)
             call readf(grid%rmax)
             !
           case default
             !
             call report ("Unrecognized unit name "//trim(w),.true.)
             !
           end select
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo
         !
         if (trim(w)/="".and.trim(w)/="END") then
            !
            call report ("Unrecognized unit name in GRID "//trim(w),.true.)
            !
         endif
         !
       case ("CONTRACTION")
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
           !
           case('VIB','ROT')
             !
             job%contraction = trim(w)
             !
           case ("VMAX","VIBMAX")
             !
             vmax = 0
             do i = 1,min(Nitems-1,Nestates)
               call readi(job%vibmax(i))
               job%vibmax(i+1:Nestates) = job%vibmax(i)
               vmax = max(vmax,job%vibmax(i))
             enddo
             !
           case("ENERMAX")
             !
             call readf(job%vibenermax)
             !
           case default
             !
             call report ("Unrecognized unit name "//trim(w),.true.)
             !
           end select
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo
         !
         if (trim(w)/="".and.trim(w)/="END") then
            !
            write (out,"('input: wrong last line in CONTRACTION =',a)") trim(w)
            stop 'input - illigal last line in CONTRACTION'
            !
         endif

         !
       case("CHECK_POINT","CHECKPOINT")
         !
         call readu(w)
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
           !
           case('EIGENFUNC','EIGENVECT','EIGENVECTORS')
             !
             call readu(w)
             !
             job%IO_eigen = trim(w)
             !
             if (all(trim(w)/=(/'READ','SAVE','NONE'/))) then 
               call report('ReadInput: illegal key in CHECK_POINT '//trim(w),.true.)
             endif 
             !
             job%eigenfile%dscr       = 'eigen_descr'
             job%eigenfile%primitives = 'eigen_quanta'
             job%eigenfile%vectors    = 'eigen_vectors'
             !
           case('TM','DIPOLE')
             !
             call readu(job%IO_dipole)
             !
             if (all(trim(w)/=(/'READ','SAVE','NONE'/))) then 
               call report('ReadInput: illegal key in CHECK_POINT '//trim(w),.true.)
             endif 
             !
           end select 
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo 
         !
         if (trim(w)/="".and.trim(w)/="END") then 
            call report('ReadInput: wrong last line in CHECK_POINTS ='//trim(w),.true.)
         endif 
         !
       case ("DIAGONALIZER","EIGESOLVER")
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
           !
           case('SYEV','SYEVR')
             !
             job%diagonalizer = trim(w)
             !
           case ("GAMMA")
             !
             i = 1
             job%select_gamma = .false.
             call readi(i_t)
             !
             do while (i_t/=0.and.i<=size(job%select_gamma))
                !
                i = i+1
                !
                job%select_gamma(i_t) = .true.
                !
                call readi(i_t)
                !
             enddo
             !
           case("NROOTS")
             !
             !call readi(job%nroots)
             !
             if (nitems-1==1) then
                !
                call readi(i)
                job%nroots(:) = i
                !
             else
               !
               if (nitems-1>20) then
                  !
                  write (out,"('input: too many entries in roots (>20): ',i8)") nitems-1
                  stop 'input - illigal number of entries in nroots'
                  !
               endif
               !
               do i =1,nitems-1
                  !
                  call readi(job%nroots(i))
                  !
               end do
               !
             endif
             !
           case("MAXITER")
             !
             call readi(job%maxiter)
             !
           case("CONTRACTION")
             !
             call readu(job%contraction)
             !
           case("TOLERANCE","TOL")
             !
             call readf(job%tolerance)
             !
           case("UPLIMIT","ENERMAX","ENERCUT")
             !
             call readf(job%upper_ener)
             !
           case("THRESHOLD","THRESH")
             !
             call readf(job%thresh)
             !
           case("ZPE")
             !
             call readf(job%zpe)
             !
           case default
             !
             call report ("Unrecognized unit name "//trim(w),.true.)
             !
           end select
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo
         !
         if (trim(w)/="".and.trim(w)/="END") then
            !
            write (out,"('input: wrong last line in DIAGONALIZER =',a)") trim(w)
            stop 'input - illigal last line in DIAGONALIZER'
            !
         endif
         !
       case("FITTING")
         !
         action%fitting = .true.
         !
         ! skip if fitting NONE
         if (Nitems>1) then
            call readu(w)
            if (trim(w)=="NONE") then
               action%fitting = .false.
               do while (trim(w)/="".and.trim(w)/="END")
                 call read_line(eof,iut) ; if (eof) exit
                 call readu(w)
               enddo
               cycle
            endif
         endif
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
              !
           case('J_LIST','JLIST','J','JROT')
             !
             i = 0
             !do while (item<Nitems.and.i<jlist_max)
             !   !
             !   i = i + 1
             !   !
             !   call readf(j_list_(i))
             !   !
             !enddo
             !
             do while (item<Nitems.and.i<jlist_max)
                !
                i = i + 1
                !
                call readu(w)
                !
                if (trim(w)/="-") then
                  !
                  read(w,*) jrot
                  !
                  j_list_(i) = jrot
                  !
                else
                  !
                  call readf(jrot2)
                  !
                  do while (item<=Nitems.and.nint(2.0*jrot)<nint(2.0*jrot2))
                    !
                    jrot = jrot + 1.0
                    j_list_(i) = jrot
                    i = i + 1
                    !
                  enddo
                  !
                  i = i - 1
                  !
                endif
                !
             enddo
             !
             fitting%nJ = i
             allocate(fitting%j_list(i),stat=alloc)
             fitting%J_list(1:i) = J_list_(1:i)
             !
           case('ITMAX','ITERMAX','ITER')
             !
             call readi(fitting%itermax)
             !
           case('ROBUST')
             !
             call readf(fitting%robust)
             !
           case('TARGET_RMS')
             !
             call readf(fitting%target_rms)
             !
           case('FIT_TYPE')
             !
             call readu(fitting%fit_type)
             !
           case('THRESH_ASSIGN','THRESH_REASSIGN','THRESH_LOCK','LOCK','LOCK_QUANTA')
             !
             call readf(fitting%threshold_lock)
             !
           case("IPARAM")
             !
             call readi(fitting%iparam(1))
             call readi(fitting%iparam(2))
             !
           case('GEOMETRIES')
             !
             call readl(fitting%geom_file)
             !
           case('OUTPUT')
             !
             call readl(fitting%output_file)
             !
           case('FIT_FACTOR')
             !
             call readf(fitting%factor)
             !
           case('ABINIIO')
             !
             ! ignore the experiment and fit to the ab initio curves only
             !
             fitting%factor = small_
             !
           case('ENER','ENERGIES','FREQ','FREQUENCY','FREQUENCIES')
             !
             if (w(1:4)=='FREQ') then
               action%frequency = .true.
             endif
             !
             Nparam_check = 0
             !
             call input_options(echo_lines=.false.)
             !
             do while (trim(w)/="END")
                !
                call read_line(eof,iut) ; if (eof) exit
                !
                call readu(w)
                !
                Nparam_check = Nparam_check+1
                !
             enddo
             !
             Nparam_check = Nparam_check-1
             !
             call input_options(echo_lines=.true.)
             !
             if (trim(w) /= "END") then
                 call report ("ERROR: Cannot find `END' statement)",.true.)
             endif
             !
             ! go back to beginning of VALUES block and reset `w' to original value
             do i=1, Nparam_check+1
               backspace(unit=iut)
             enddo
             !
             fitting%Nenergies = Nparam_check
             !
             !call readi(fitting%Nenergies)
             !
             allocate (fitting%obs(1:fitting%Nenergies),stat=alloc)
             if (alloc/=0) then
               write (out,"(' Error ',i0,' initializing obs. energy related arrays')") alloc
               stop 'obs. energy arrays - alloc'
             end if
             !
             iobs = 0
             !
             call read_line(eof,iut) ; if (eof) exit
             call readu(w)
             !
             do while (trim(w)/="END".and.iobs<fitting%Nenergies)
                !
                iobs = iobs + 1
                !
                if (.not.action%frequency.and.nitems<9) then
                   call report('input: wrong number of records in obs_fitting_energies (maybe using old input and need to add omega)',.true.)
                endif
                !
                if (action%frequency.and.nitems<16) then
                   call report('input: wrong number of records in obs_fitting_frequency (maybe line is too long (>300) or old input and need to add omega)',.true.)
                endif
                !
                read(w,"(f9.1)") fitting%obs(iobs)%Jrot
                !
                ! get the index number of the current Jrot in J_list
                !
                i = 0
                matchfound = .false.
                do while( i<fitting%nJ.and..not.matchfound )
                  !
                  i = i + 1
                  if (fitting%J_list(i)/=fitting%obs(iobs)%Jrot) cycle
                  matchfound = .true.
                  !
                enddo
                !
                ! skip current line if these Jrot-s are not processed
                if (.not.matchfound) then
                  iobs = iobs-1
                  call read_line(eof,iut) ; if (eof) exit
                  call readu(w)
                  cycle
                endif
                !
                fitting%obs(iobs)%irot = i
                !
                ! parity:
                !
                call readu(w)
                !
                select case(w)
                  !
                case ('E')
                  !
                  if ( mod( nint( 2.0*fitting%obs(iobs)%Jrot ),2 )==1 ) then
                    itau = mod( nint( fitting%obs(iobs)%Jrot-0.5 ),2 )
                  else
                    itau = mod( nint( fitting%obs(iobs)%Jrot ),2 )
                  endif
                  !
                case ('F')
                  !
                  if ( mod( nint( 2.0*fitting%obs(iobs)%Jrot ),2 )==1 ) then
                    itau = mod( nint( fitting%obs(iobs)%Jrot-0.5 )+1,2 )
                  else
                    itau = mod( nint( fitting%obs(iobs)%Jrot )+1,2 )
                  endif
                  !
                case ('+')
                  !
                  itau = 0
                  !
                case ('-')
                  !
                  itau = 1
                  !
                case default
                  !
                  read(w,"(i2)") itau
                  !
                end select
                !
                fitting%obs(iobs)%iparity = itau
                !
                call readi(fitting%obs(iobs)%N)
                !
                if (action%frequency) then
                  call readf(fitting%obs(iobs)%Jrot_)
                  !
                  i = 0 
                  matchfound = .false.
                  do while( i<fitting%nJ.and..not.matchfound )
                    !
                    i = i + 1
                    if (fitting%J_list(i)/=fitting%obs(iobs)%Jrot_) cycle
                    matchfound = .true.
                    !
                  enddo
                  !
                  ! skip current line if these Jrot-s are not processed
                  if (.not.matchfound) then
                    iobs = iobs-1
                    call read_line(eof,iut) ; if (eof) exit
                    call readu(w)
                    cycle
                  endif
                  !
                  fitting%obs(iobs)%irot_ = i
                  !
                  ! parity:
                  !
                  call readu(w)
                  !
                  select case(w)
                    !
                  case ('E')
                    !
                    if ( mod( nint( 2.0*fitting%obs(iobs)%Jrot_ ),2 )==1 ) then
                      itau = mod( nint( fitting%obs(iobs)%Jrot_-0.5 ),2 )
                    else
                      itau = mod( nint( fitting%obs(iobs)%Jrot_ ),2 )
                    endif
                    !
                  case ('F')
                    !
                    if ( mod( nint( 2.0*fitting%obs(iobs)%Jrot_ ),2 )==1 ) then
                      itau = mod( nint( fitting%obs(iobs)%Jrot_-0.5 )+1,2 )
                    else
                      itau = mod( nint( fitting%obs(iobs)%Jrot_ )+1,2 )
                    endif
                    !
                  case ('+')
                    !
                    itau = 0
                    !
                  case ('-')
                    !
                    itau = 1
                    !
                  case default
                    !
                    read(w,"(i2)") itau
                    !
                  end select
                  !
                  fitting%obs(iobs)%iparity_ = itau
                  !
                  call readi(fitting%obs(iobs)%N_)
                  !
                  call readf(fitting%obs(iobs)%energy)
                  !
                else
                  call readf(fitting%obs(iobs)%energy)
                endif
                !
                call readi(fitting%obs(iobs)%quanta%istate)
                !
                ! skip current line if this state is not processed
                !
                if (fitting%obs(iobs)%quanta%istate>Nestates) then
                  iobs = iobs-1
                  call read_line(eof,iut) ; if (eof) exit
                  call readu(w)
                  cycle
                endif
                !
                call readi(fitting%obs(iobs)%quanta%v)
                call readi(fitting%obs(iobs)%quanta%ilambda)
                call readf(fitting%obs(iobs)%quanta%sigma)
                !
                if (.not.action%frequency.and.nitems==9) then
                  ! old input where omega was not present
                  !
                  fitting%obs(iobs)%quanta%omega = fitting%obs(iobs)%quanta%sigma + real(fitting%obs(iobs)%quanta%ilambda,rk)
                  !
                else
                  !
                  call readf(fitting%obs(iobs)%quanta%omega)
                  !
                endif
                !
                fitting%obs(iobs)%quanta%spin = poten(fitting%obs(iobs)%quanta%istate)%spini
                !
                if (action%frequency) then
                  !
                  call readi(fitting%obs(iobs)%quanta_%istate)
                  !
                  ! skip current line if this state is not processed
                  !
                  if (fitting%obs(iobs)%quanta_%istate>Nestates) then
                    iobs = iobs-1
                    call read_line(eof,iut) ; if (eof) exit
                    call readu(w)
                    cycle
                  endif
                  !
                  call readi(fitting%obs(iobs)%quanta_%v)
                  call readi(fitting%obs(iobs)%quanta_%ilambda)
                  call readf(fitting%obs(iobs)%quanta_%sigma)
                  call readf(fitting%obs(iobs)%quanta_%omega)
                  !
                  fitting%obs(iobs)%quanta_%spin = poten(fitting%obs(iobs)%quanta_%istate)%spini
                  !
                  !fitting%obs(iobs)%quanta_%omega = fitting%obs(iobs)%quanta_%sigma + real(fitting%obs(iobs)%quanta_%ilambda,rk)
                  !
                endif
                !
                if (fitting%obs(iobs)%quanta%istate>Nestates.or.fitting%obs(iobs)%quanta%istate<1) then
                   call report('input: illegal state',.true.)
                endif
                !
                !call readf(fitting%obs(i)%quanta%omega)
                !
                !if (abs(fitting%obs(i)%quanta%sigma)>fitting%obs(i)%quanta%spin) then
                !   call report('input: sigma is large than spin',.true.)
                !endif
                !
                call readf(fitting%obs(iobs)%weight)
                !
                !if (fitting%obs(iobs)%Jrot<jmin.or.fitting%obs(iobs)%Jrot>jmax.or.&
                !   (action%frequency.and.fitting%obs(iobs)%Jrot_<jmin.or.fitting%obs(iobs)%Jrot_>jmax) ) then
                !    iobs = iobs-1
                !endif
                !
                call read_line(eof,iut) ; if (eof) exit
                call readu(w)
                !
             enddo
             !
           case default
             !
             call report ("Unrecognized unit name "//trim(w),.true.)
             !
           end select
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo
         !
         fitting%Nenergies = iobs
         !
         if (trim(w)/="".and.trim(w)/="END") then
            call report ('wrong last line in FITTING ',.false.)
         endif
          !
       case("SPIN-ORBIT","SPIN-ORBIT-X","POTEN","POTENTIAL","L2","L**2","LXLY","LYLX","ABINITIO",&
            "LPLUS","L+","L_+","LX","DIPOLE","TM","DIPOLE-MOMENT","DIPOLE-X",&
            "SPIN-SPIN","SPIN-SPIN-O","BOBROT","BOB-ROT","SPIN-ROT","DIABATIC","DIABAT",&
            "LAMBDA-OPQ","LAMBDA-P2Q","LAMBDA-Q","LAMBDAOPQ","LAMBDAP2Q","LAMBDAQ") 
          !
          ibraket = 0
          !
          ! initializing units
          unit_field = 1 ; unit_r = 1
          !
          select case (w)
             !
          case("DIPOLE","TM","DIPOLE-MOMENT","DIPOLE-X")
             !
             if (idip==0) then 
                allocate(dipoletm(ncouples),stat=alloc)
             endif
             !
             idip = idip + 1
             !
             call readi(iref)
             call readi(jref)
             !
             include_state = .false.
             loop_istated : do istate=1,Nestates
               do jstate=1,Nestates
                 !
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istated
                 endif
                 !
               enddo
             enddo loop_istated
             !
             if (.not.include_state) then
                 write(out,"('The interaction ',2i8,' is skipped')") iref,jref
                 idip = idip - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             if (idip>ncouples) then
                 print "(2a,i4,a,i6)",trim(w),": Number of dipoles = ",idip," exceeds the maximal allowed value",ncouples
                 call report ("Too many couplings given in the input for"//trim(w),.true.)
             endif
             !
             field => dipoletm(idip)
             !
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%lambda  = -10000
             field%lambdaj = -10000
             field%jref = jref
             field%class = "DIPOLE"
             !
             if (trim(w)=='DIPOLE-X') then
               field%molpro = .true.
             endif
             !
          case("SPIN-ORBIT","SPIN-ORBIT-X")
             !
             iobject(2) = iobject(2) + 1
             !
             call readi(iref)
             call readi(jref)
             !
             include_state = .false.
             loop_istate : do istate=1,Nestates
               do jstate=1,Nestates
                 !
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate
                 endif
                 !
               enddo
             enddo loop_istate
             !
             if (.not.include_state) then
                 write(out,"('The interaction ',2i8,' is skipped')") iref,jref
                 iobject(2) = iobject(2) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             iso = iobject(2)
             !
             if (iso>ncouples) then
                 print "(2a,i4,a,i6)",trim(w),": Number of couplings = ",iso," exceeds the maximal allowed value",ncouples
                 call report ("Too many couplings given in the input for"//trim(w),.true.)
             endif
             !
             field => spinorbit(iso)
             !
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%lambda  = -10000
             field%lambdaj = -10000
             field%sigmai  = -10000.0
             field%sigmaj  = -10000.0
             !
             if (action%fitting) call report ("SPIN-ORBIT cannot appear after FITTING",.true.)
             field%class = "SPINORBIT"
             !
             if (trim(w)=='SPIN-ORBIT-X') then
               field%molpro = .true.
             endif
             !
          case("LXLY","LYLX","L+","L_+","LX")
             !
             iobject(4) = iobject(4) + 1
             !
             call readi(iref)
             call readi(jref)
             !
             include_state = .false.
             loop_istatex : do istate=1,Nestates
               do jstate=1,Nestates
                 !
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istatex
                 endif
                 !
               enddo
             enddo loop_istatex
             !
             if (.not.include_state) then
                 write(out,"('The interaction ',2i8,' is skipped')") iref,jref
                 iobject(4) = iobject(4) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             ilxly = iobject(4)
             !
             if (ilxly>ncouples) then
                 print "(2a,i4,a,i6)",trim(w),": Number of L+ couplings = ",ilxly," exceeds the maximal allowed value",ncouples
                 call report ("Too many L+ couplings given in the input for"//trim(w),.true.)
             endif
             !
             field => lxly(ilxly)
             !
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "L+"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("LXLY (L+) cannot appear after FITTING",.true.)
             !
             if (trim(w)=='LX') then
               field%molpro = .true.
             endif
             !
          case("POTEN","POTENTIAL")
             !
             iobject(1) = iobject(1) + 1
             !
             if (iobject(1)>nestates) then
                 print "(a,i4,a,i6)","The state # ",iobject(1)," is not included for the total number of states",nestates
                 !call report ("Too many potentials given in the input",.true.)
                 iobject(1) = iobject(1) - 1
                 !
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 !
                 !call read_line(eof,iut) ; if (eof) exit
                 !call readu(w)
                 cycle
             endif
             !
             ipot = iobject(1)
             !
             field => poten(iobject(1))
             field%istate = iobject(1)
             !
             call readi(field%iref)
             field%jref = field%iref
             field%class = "POTEN"
             !
             if (action%fitting) call report ("POTEN cannot appear after FITTING",.true.)
             !
          case("L2","L**2", "L^2")
             !
             iobject(3) = iobject(3) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! for nondiagonal L2 terms
             if (nitems>2) call readi(jref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_l2 : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_l2
                 endif
               enddo
             enddo loop_istate_l2
             !
             if (.not.include_state) then
                 write(out,"('The L2 term ',2i8,' is skipped')") iref,jref
                 iobject(3) = iobject(3) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             il2 = iobject(3)
             !
             field => l2(il2)
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "L2"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("L2 cannot appear after FITTING",.true.)
             !
             !
          case("BOB-ROT","BOBROT")
             !
             iobject(7) = iobject(7) + 1
             !
             call readi(iref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_bobrot : do istate=1,Nestates
                 if (iref==poten(istate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   exit loop_istate_bobrot
                 endif
             enddo loop_istate_bobrot
             !
             if (.not.include_state) then
                 write(out,"('The BOB-ROT term ',1i8,' is skipped')") iref
                 iobject(7) = iobject(7) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             ibobrot = iobject(7)
             !
             field => bobrot(ibobrot)
             field%iref = iref
             field%jref = iref
             field%istate = istate_
             field%jstate = istate_
             field%class = "BOBROT"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("BOBrot cannot appear after FITTING",.true.)
             !
          case("SPIN-SPIN")
             !
             iobject(5) = iobject(5) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_ss : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_ss
                 endif
               enddo
             enddo loop_istate_ss
             !
             if (.not.include_state) then
                 write(out,"('The SS term ',2i8,' is skipped')") iref,jref
                 iobject(5) = iobject(5) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             iss = iobject(5)
             !
             field => spinspin(iss)
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "SPIN-SPIN"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("Spin-spin cannot appear after FITTING",.true.)
             !
             ! non-diagonal spin-spin term 
             !
          case("SPIN-SPIN-O")
             !
             iobject(6) = iobject(6) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_sso : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_sso
                 endif
               enddo
             enddo loop_istate_sso
             !
             if (.not.include_state) then
                 write(out,"('The SS-o term ',2i8,' is skipped')") iref,jref
                 iobject(6) = iobject(6) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             isso = iobject(6)
             !
             field => spinspino(isso)
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "SPIN-SPIN-O"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("Spin-spin-o cannot appear after FITTING",.true.)
             !
          case("SPIN-ROT")
             !
             ! spin-rotation (gammma) term 
             !
             iobject(8) = iobject(8) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_sr : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_sr
                 endif
               enddo
             enddo loop_istate_sr
             !
             if (.not.include_state) then
                 write(out,"('The SR term ',2i8,' is skipped')") iref,jref
                 iobject(8) = iobject(8) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             isr = iobject(8)
             !
             field => spinrot(isr)
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "SPIN-ROT"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("Spin-rot cannot appear after FITTING",.true.)
             !
          case("DIABAT","DIABATIC")
             !
             iobject(9) = iobject(9) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! for nondiagonal terms
             if (nitems>2) call readi(jref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_diab : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_diab
                 endif
               enddo
             enddo loop_istate_diab
             !
             if (.not.include_state) then
                 write(out,"('The DIABATIC term ',2i8,' is skipped')") iref,jref
                 iobject(9) = iobject(9) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             idiab = iobject(9)
             !
             field => diabatic(idiab)
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = "DIABATIC"
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report ("DIABATIC cannot appear after FITTING",.true.)
             !
          case("LAMBDA-OPQ","LAMBDAOPQ")  ! o+p+q
             !
             iobject(10) = iobject(10) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! for nondiagonal terms
             if (nitems>2) call readi(jref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_10 : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_10
                 endif
               enddo
             enddo loop_istate_10
             !
             if (.not.include_state) then
                 write(out,"('The LAMBDA-O term ',2i8,' is skipped')") iref,jref
                 iobject(10) = iobject(10) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             field => lambdaopq(iobject(10))
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = trim(CLASSNAMES(10))
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report (trim(field%class)//" cannot appear after FITTING",.true.)
             !
             ! -(p+2q)
             !
          case("LAMBDA-P2Q","LAMBDAP2Q")
             !
             iobject(11) = iobject(11) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! for nondiagonal terms
             if (nitems>2) call readi(jref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_11 : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_11
                 endif
               enddo
             enddo loop_istate_11
             !
             if (.not.include_state) then
                 write(out,"('The LAMBDA-P term ',2i8,' is skipped')") iref,jref
                 iobject(11) = iobject(11) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             field => lambdap2q(iobject(11))
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = trim(CLASSNAMES(11))
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report (trim(field%class)//" cannot appear after FITTING",.true.)
             !
          case("LAMBDA-Q","LAMBDAQ")
             !
             iobject(12) = iobject(12) + 1
             !
             call readi(iref) ; jref = iref
             !
             ! for nondiagonal terms
             if (nitems>2) call readi(jref)
             !
             ! find the corresponding potential
             !
             include_state = .false.
             loop_istate_12 : do istate=1,Nestates
               do jstate=1,Nestates
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   include_state = .true.
                   istate_ = istate
                   jstate_ = jstate
                   exit loop_istate_12
                 endif
               enddo
             enddo loop_istate_12
             !
             if (.not.include_state) then
                 write(out,"('The LAMBDA-Q term ',2i8,' is skipped')") iref,jref
                 iobject(12) = iobject(12) - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             field => lambdaq(iobject(12))
             field%iref = iref
             field%jref = jref
             field%istate = istate_
             field%jstate = jstate_
             field%class = trim(CLASSNAMES(12))
             field%lambda  = -10000
             field%lambdaj = -10000
             !
             if (action%fitting) call report (trim(field%class)//" cannot appear after FITTING",.true.)
             !
           case("ABINITIO")
             !
             iabi = iabi + 1
             !
             call readu(w)
             !
             jref = 0
             jstate_ = 0
             iabi_ = 0
             !
             select case (w)
               !
             case ("POTEN","POTENTIAL")
               !
               ! find the corresponding potential
               !
               call readi(iref)
               !
               include_state = .false.
               loop_istate_abpot : do istate=1,Nestates
                   if (iref==poten(istate)%iref) then
                     include_state = .true.
                     !istate_ = istate
                     iabi_ = istate
                     exit loop_istate_abpot
                   endif
               enddo loop_istate_abpot
               !
             case("L2","L**2")
               !
               ! find the corresponding L2
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_abl2 : do i=1,NL2
                   if (iref==l2(i)%iref.and.jref==l2(i)%jref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + i
                     !
                     exit loop_istate_abl2
                   endif
               enddo loop_istate_abl2

             case("BOB-ROT","BOBROT")
               !
               ! find the corresponding BB
               !
               call readi(iref) ; jref = iref
               !
               include_state = .false.
               loop_istate_abbobr : do i=1,NL2
                   if (iref==bobrot(i)%iref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + il2 + ilxly + iss+isso+i
                     !
                     exit loop_istate_abbobr
                   endif
               enddo loop_istate_abbobr
               !
             case("SPIN-ORBIT","SPIN-ORBIT-X")
               !
               call readi(iref)
               call readi(jref)
               !
               include_state = .false.
               loop_istate_abiso : do i=1,iso
                   !
                   if (iref==spinorbit(i)%iref.and.jref==spinorbit(i)%jref) then
                     include_state = .true.
                     !
                     iabi_ = Nestates + i
                     !
                     exit loop_istate_abiso
                   endif
                   !
               enddo loop_istate_abiso
               !
               if (trim(w)=='SPIN-ORBIT-X') then
                 field%molpro = .true.
               endif
               !
             case("LXLY","LYLX","L+","L_+","LX")
               !
               call readi(iref)
               call readi(jref)
               !
               include_state = .false.
               loop_istatex_abi : do i=1,ilxly
                   !
                   if (iref==lxly(i)%iref.and.jref==lxly(i)%jref) then
                     include_state = .true.
                     !
                     iabi_ = Nestates + iso + il2 + i
                     !
                     exit loop_istatex_abi
                   endif
                   !
               enddo loop_istatex_abi
               !
               if (trim(w)=='LX') then
                 field%molpro = .true.
               endif
               !
             case("SPIN-SPIN")
               !
               ! find the corresponding SS
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_abss : do i=1,iss
                   if (iref==spinspin(i)%iref.and.jref==spinspin(i)%jref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + il2 + ilxly + i
                     !
                     exit loop_istate_abss
                   endif
               enddo loop_istate_abss
               !
             case("SPIN-SPIN-O")
               !
               ! find the corresponding SSO
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_absso : do i=1,isso
                   if (iref==spinspino(i)%iref.and.jref==spinspino(i)%jref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + il2 + ilxly + iss+i
                     !
                     exit loop_istate_absso
                   endif
               enddo loop_istate_absso
               !
             case("SPIN-ROT")
               !
               ! find the corresponding object
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_absr : do i=1,isr
                   if (iref==spinrot(i)%iref.and.jref==spinrot(i)%jref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + il2 + ilxly + iss + isso + ibobrot + i
                     !
                     exit loop_istate_absr
                   endif
               enddo loop_istate_absr
               !
             case("DIABATIC","DIABAT")
               !
               ! find the corresponding object
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_abdia : do i=1,idiab
                   if (iref==diabatic(i)%iref.and.jref==diabatic(i)%jref) then
                     include_state = .true.
                     !istate_ = istate
                     !
                     iabi_ = Nestates + iso + il2 + ilxly + iss + isso + ibobrot + isr + i
                     !
                     exit loop_istate_abdia
                   endif
               enddo loop_istate_abdia
               !
             case("LAMBDA-OPQ","LAMBDAOPQ")
               !
               ! find the corresponding object
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_ab10 : do i=1,iobject(10)
                   if (iref==lambdaopq(i)%iref.and.jref==lambdaopq(i)%jref) then
                     include_state = .true.
                     !
                     iabi_ = sum(iobject(1:Nobjects-4)) + i
                     !
                     exit loop_istate_ab10
                   endif
               enddo loop_istate_ab10
               !
             case("LAMBDA-P2Q","LAMBDAP2Q")
               !
               ! find the corresponding object
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_ab11 : do i=1,iobject(11)
                   if (iref==lambdap2q(i)%iref.and.jref==lambdap2q(i)%jref) then
                     include_state = .true.
                     !
                     iabi_ = sum(iobject(1:Nobjects-4)) + i
                     !
                     exit loop_istate_ab11
                   endif
               enddo loop_istate_ab11

               !
             case("LAMBDA-Q","LAMBDAQ")
               !
               ! find the corresponding object
               !
               call readi(iref) ; jref = iref
               if (nitems>2) call readi(jref)
               !
               include_state = .false.
               loop_istate_ab12 : do i=1,iobject(12)
                   if (iref==lambdaq(i)%iref.and.jref==lambdaq(i)%jref) then
                     include_state = .true.
                     !
                     iabi_ = sum(iobject(1:Nobjects-4)) + i
                     !
                     exit loop_istate_ab12
                   endif
               enddo loop_istate_ab12
               !
             end select
             !
             if (.not.include_state) then
                 write(out,"('The ab potential  ',i8,' is skipped')") iref
                 iabi = iabi - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             field => abinitio(iabi_)
             !
             field%iref = iref
             field%jref = jref
             !
             field%refvalue = 0
             !
             !field%istate = istate_
             !field%jstate = jstate_
             !
             if (.not.include_state) then
                 write(out,"('The ab potential  ',i8,' is skipped')") iref
                 iabi = iabi - 1
                 do while (trim(w)/="".and.trim(w)/="END")
                   call read_line(eof,iut) ; if (eof) exit
                   call readu(w)
                 enddo
                 cycle
             endif
             !
             field => abinitio(iabi_)
             !
             field%iref = iref
             field%jref = jref
             field%class = "ABINITIO"//trim(w)
             !
             field%refvalue = 0
             !
             loop_istate_ai : do istate=1,Nestates
               do jstate=1,Nestates
                 !
                 if (iref==poten(istate)%iref.and.jref==poten(jstate)%iref) then
                   field%istate = istate
                   field%jstate = jstate
                   exit loop_istate_ai
                 endif
                 !
               enddo
             enddo loop_istate_ai
             !
          case default
             call report ("Unrecognized unit name "//trim(w),.true.)
          end select
          !
          ! refnumbers of the states to couple
          !
          call read_line(eof,iut) ; if (eof) exit
          call readu(w)
          !
          do while (trim(w)/="".and.trim(w)/="END")
            !
            select case(w)
            !
            case("INTERPOLATIONTYPE")
              !
              call readu(w)
              field%interpolation_type = trim(w)
              !
            case("TYPE")
              !
              call readu(w)
              !
              field%type = trim(w)
              !
            case("NAME")
              !
              call reada(w)
              !
              field%name = trim(w)
              !
            case("OMEGA")
              !
              call readi(field%omega)
              !
            case("LAMBDA")
              !
              call readi(field%lambda)
              field%lambdaj = field%lambda
              if (nitems>2) call readi(field%lambdaj)
              !
            case("SHIFT","REFVALUE","REF","F1","V0","VE")
              !
              call readf(field%refvalue)
              !
            case("<X|LZ|Y>")
              !
              if (nitems<=2) call report ("Too few entries in "//trim(w),.true.)
              !
              item_ = 1
              do while (trim(w)/="".and.trim(w)/="END".and.item_<nitems)
                !
                call readu(w)
                !
                item_ = item_ + 1
                !
                select case (trim(w))
                  !
                case('0')
                  x_lz_y_ = 0
                case('I')
                  x_lz_y_ = 1
                case('-I')
                  x_lz_y_ = -1
                case('2*I','2I','I*2')
                  x_lz_y_ = 2
                case('-2*I','-2I','-I*2')
                  x_lz_y_ = -2
                case('3*I','3I','I*3')
                  x_lz_y_ = 3
                case('-3*I','-3I','-I*3')
                  x_lz_y_ = -3
                case('4*I','4I','I*4')
                  x_lz_y_ = 4
                case('-4*I','-4I','-I*4')
                  x_lz_y_ = -4
                case('5*I','5I','I*5')
                  x_lz_y_ = 5
                case('-5*I','-5I','-I*5')
                  x_lz_y_ = -5
                case('6*I','6I','I*6')
                  x_lz_y_ = 6
                case('-6*I','-6I','-I*6')
                  x_lz_y_ = -6
                !case('(-I)*N')
                !  call readi(x_lz_y_)
                case default
                  call report ("Illegal input field"//trim(w)//"; SHOULD BE IN THE FORM I, -I, 2*I, -2*I...,(-i)*N",.true.)
                end select
                !
                if (item_==2) then
                  !
                  field%ix_lz_y = x_lz_y_
                  !
                  if (poten(field%istate)%ix_lz_y==0) poten(field%istate)%ix_lz_y = field%ix_lz_y
                  !
                  if (poten(field%istate)%ix_lz_y/=field%ix_lz_y) then
                    !
                    write(out,"('input: ',a,2i4,' <x|lz|y> disagree with the poten-value ',2i8)") & 
                            field%class,field%iref,field%jref,poten(field%istate)%ix_lz_y/=field%ix_lz_y
                    call report (" <x|lz|y> disagree with the poten-value",.true.)
                    !
                  endif
                  !
                elseif(item_==3) then
                  !
                  field%jx_lz_y = x_lz_y_
                  !
                  ! poten can have only one ix_lz_y, i.e. diagonal, its jx_lz_y should not be used
                  !
                  if (poten(field%jstate)%ix_lz_y==0) poten(field%jstate)%ix_lz_y = field%jx_lz_y
                  !
                  if (poten(field%jstate)%ix_lz_y/=field%jx_lz_y) then
                    !
                    write(out,"('input: ',a,2i4,' <x|lz|y> disagree with the poten-value ',2i8)") & 
                            field%class,field%iref,field%jref,poten(field%istate)%ix_lz_y/=field%jx_lz_y
                    call report (" <x|lz|y> disagree with the poten-value",.true.)
                    !
                  endif
                endif
                !
              enddo                
              !
            case("UNITS")
              !
              item_ = 1
              do while (trim(w)/="".and.trim(w)/="END".and.item_<nitems)
                !
                call readu(w)
                !
                item_ = item_ + 1
                !
                select case(w)
                  !
                case ('BOHR', 'BOHRS')
                  !
                  unit_r = bohr
                  !
                case ('ANG','ANGSTROM','ANGSTROMS')
                  !
                  unit_r = 1.0_rk
                  !
                case ('CM-1')
                  !
                  unit_field = 1.0_rk
                  !
                case ('EV')
                  !
                  unit_field = ev
                  !
                case ('HARTREE','EH','A.U.', 'AU')
                  !
                  unit_field = hartree
                  !
                case ('EA0')
                  !
                  unit_field = todebye
                  !
                case ('DEBYE')
                  !
                  unit_field = 1.0_rk
                  !
                case default
                  !
                  call report ("Illegal input field"//trim(w),.true.)
                  !
                end select
                !
              enddo
              !
            case("SYM","SYMMETRY")
              !
              item_ = 1
              do while (trim(w)/="".and.trim(w)/="END".and.item_<nitems)
                !
                call readu(w)
                !
                item_ = item_ + 1
                !
                select case(w)
                  !
                case ('G')
                  !
                  field%parity%gu = 1
                  !
                case ('U')
                  !
                  field%parity%gu = -1
                  !
                case ('+')
                  !
                  field%parity%pm = 1
                  !
                case ('-')
                  !
                  field%parity%pm = -1
                  !
                case default
                  !
                  call report ("Illegal input field"//trim(w),.true.)
                  !
                end select
                !
              enddo
              !
            case("MORPHING","MORPH")
              !
              field%morphing = .true.
              !
            case("MOLPRO")
              !
              field%molpro = .true.
              !
            case("FACTOR")
              !
              field%complex_f = cmplx(1.0_rk,0.0_rk)
              field%factor = 1.0_rk
              !
              do while (item<min(Nitems,3))
                !
                call readu(w)
                !
                select case (trim(w))
                  !
                case('I')
                  field%complex_f = cmplx(0.0_rk,1.0_rk)
                case('-I')
                  field%complex_f = cmplx(0.0_rk,-1.0_rk)
                case('SQRT(2)')
                  field%factor =  sqrt(2.0_rk)
                case('-SQRT(2)')
                  field%factor = -sqrt(2.0_rk)
                case default
                  read(w,*) field%factor
                end select
                !
             enddo
             !
             !
            case("FIT_FACTOR")
              !
              call readf(field%fit_factor)
              !
            case("COMPLEX")
              !
              call readu(w)
              !
              select case (trim(w))
                !
              case('0')
                field%complex_f = cmplx(0.0_rk,0.0_rk)
              case('I')
                field%complex_f = cmplx(0.0_rk,1.0_rk)
              case('-I')
                field%complex_f = cmplx(0.0_rk,-1.0_rk)
              case('1')
                field%complex_f = cmplx(1.0_rk,0.0_rk)
              case('SQRT(2)')
                field%complex_f = cmplx(sqrt(2.0_rk),0.0_rk)
              case('-SQRT(2)')
                field%complex_f = cmplx(-sqrt(2.0_rk),0.0_rk)
              case('I*SQRT(2)')
                field%complex_f = cmplx(0.0_rk,sqrt(2.0_rk))
              case('-I*SQRT(2)')
                field%complex_f = cmplx(0.0_rk,-sqrt(2.0_rk))
              case default
                call report ("Illegal input field"//trim(w),.true.)
              end select
              !
            case("<")
              !
              call report ("Braket input structure < | | > is obsolete ",.true.)
              !
              if (Nitems/=9) call report ("Illegal number of characters in the bra-ket field, has to be 9",.true.)
              !
              field%nbrakets = field%nbrakets + 1
              ibraket = ibraket + 1
              !
              if (ibraket>4) then
                 write(out,'("Two many bra-kets = ",i4," (maximum 4) ")') ibraket
                 call report ("Two many bra-kets ",.true.)
              endif
              !
              call readi(field%braket(ibraket)%ilambda)
              call readf(field%braket(ibraket)%sigmai)
              !
              call readu(w)
              if (trim(w)/="|") call report ("Illegal character between bra and ket, has to be a bar |"//trim(w),.true.)
              !
              call readi(field%braket(ibraket)%jlambda)
              call readf(field%braket(ibraket)%sigmaj)
              call readu(w)
              if (trim(w)/=">") call report ("Illegal character after the bra-ket, has to be >"//trim(w),.true.)
              call readu(w)
              if (trim(w)/="=") call report ("Illegal character before the value of the bra-ket, has to be ="//trim(w),.true.)
              !
              call readf(field%braket(ibraket)%value)
              !
              istate = field%istate
              jstate = field%jstate
              !
              if (abs(field%braket(ibraket)%ilambda)/=poten(istate)%lambda.or. &
                  abs(field%braket(ibraket)%jlambda)/=poten(jstate)%lambda) then
                write(out,'("bra-ket lambdas (",2i4,") do not agree with the state lambdas (",2i4,") ")') &
                           field%braket(ibraket)%ilambda, & 
                           field%braket(ibraket)%jlambda,poten(istate)%lambda,poten(jstate)%lambda
                stop "Illegal bra-ket lambdas"
              endif
              !
              if ( nint( abs( 2.0*field%braket(ibraket)%sigmai ) )>nint( 2.0*field%spini ) .or. &
                   nint( abs( 2.0*field%braket(ibraket)%sigmaj ) )>nint( 2.0*field%spinj ) ) then
                write(out,'("bra-ket sigmai (",2f8.1,") greater than the field spini (",2f8.1,") ")') &
                            field%braket(ibraket)%sigmai,field%braket(ibraket)%sigmaj,field%spini,field%spinj
                stop "Illegal bra-ket sigmai"
              endif
              !
            case("SIGMA")
              !
              call readf(field%sigmai)
              field%sigmaj = field%sigmai
              if (nitems>2) call readf(field%sigmaj)
              !
            case("SPIN")
              !
              call readf(field%spini)
              field%spinj = field%spini
              if (nitems>2) call readf(field%spinj)
              !
              if (mod(nint(2.0_rk*field%spini+1.0_rk),2)==0.and.integer_spin) then
                call report("The multiplicity of j-s in J_lits are inconcistent with the SPIN of the field defined at:",.true.)
              endif
              !
            case("MULT","MULTIPLICITY")
              !
              call readi(field%multi)
              !
              if (mod(field%multi,2)==0.and.integer_spin) then
                !
                write(out,'(A,i4," of the field ",i4," is inconsistent with multiplicity of jmin/jmax = ",2f8.1)') &
                            "The multiplicity ", field%multi,field%iref,jmin,jmax
                call report("The multiplicity of the field is inconsistent with jmin/jmax")
                !
              endif
              !
              !if (mod(field%multi,2)==0) integer_spin = .true.
              !
              field%spini = real(field%multi-1,rk)*0.5_rk
              !
              field%jmulti = field%multi
              if (nitems>2) then
                call readi(field%jmulti)
                field%spinj = real(field%jmulti-1,rk)*0.5_rk
              endif
              !
            case("NPARAM","N","NPOINTS")
              !
              call readi(Nparam)
              !
              if (Nparam<0) then
                  call report ("The size of the potential is illegar (<1)",.true.)
              endif
              !
              field%Nterms = Nparam
              !
            case("VALUES")
              !
              ! by Lorenzo Lodi
              ! find the number of points/parameters in input
              !
              Nparam_check = 0
              !write(my_fmt, '(A,I0,A)') '(A',cl,')'
              !
              call input_options(echo_lines=.false.)
              !
              do while (trim(w)/="END")
                 !
                 call read_line(eof,iut) ; if (eof) exit
                 !
                 call readu(w)
                 !
                 Nparam_check = Nparam_check+1
                 !
              enddo
              !
              Nparam_check = Nparam_check-1
              !
              call input_options(echo_lines=.true.)
              !
              if (trim(w) /= "END") then
                  call report ("ERROR: Cannot find `END' statement)",.true.)
              endif
              !
              ! go back to beginning of VALUES block and reset `w' to original value
              do i=1, Nparam_check+1
                backspace(unit=iut)
              enddo
              !
              w = "VALUES"
              !
              Nparam = Nparam_check
              !
              if (Nparam <= 0) then
                  call report ("ERROR: Number of points or parameters <= 0 )",.true.)
              endif
              !
              field%Nterms = Nparam
              !
              ! Allocation of the pot. parameters
              !
              allocate(field%value(Nparam),field%forcename(Nparam),field%grid(Nparam),field%weight(Nparam),stat=alloc)
              call ArrayStart(trim(field%type),alloc,Nparam,kind(field%value))
              call ArrayStart(trim(field%type),alloc,Nparam,kind(field%grid))
              call ArrayStart(trim(field%type),alloc,Nparam,kind(field%weight))
              !
              allocate(field%link(Nparam),stat=alloc)
              call ArrayStart(trim(field%type),alloc,3*Nparam,ik)
              !
              field%value = 0
              field%forcename = 'dummy'
              field%weight = 0
              !
              iparam = 0
              !
              do while (trim(w)/="".and.iparam<Nparam.and.trim(w)/="END")
                 !
                 call read_line(eof,iut) ; if (eof) exit
                 !
                 iparam = iparam+1
                 !
                 select case(trim(field%type))
                 !
                 case("GRID")
                   !
                   call readu(w)
                   !
                   if (trim(w)=="END") call report("Two many grid-entries in the field "//trim(field%name)// &
                                                                                " (or N is too small)",.true.)
                   !
                   !call readf(f_t)
                   read(w,*) f_t
                   field%grid(iparam) = f_t*unit_r
                   !
                   call readf(f_t)
                   field%value(iparam) = f_t*unit_field
                   !
                   if (Nitems>=3) call readf(field%weight(iparam))
                   !
                 case ("NONE")
                   !
                   call report ("The field type (e.g. GRID) is undefined for the current filed "//trim(w),.true.)
                   !
                 case default
                   !
                   if (nitems<2) then
                      !
                      write(out,"(a,i4)") "wrong number of records for an analytical field-type," // &
                                      "must be two at least (name value)",nitems
                      call report ("illegal number of records (<2) in the current field-line "//trim(w),.true.)
                      !
                   endif
                   !
                   ! these fields are to link to other parameters in the refinement
                   !
                   field%link(iparam)%iobject = 0
                   field%link(iparam)%ifield = 0
                   field%link(iparam)%iparam = 0
                   !
                   call readu(field%forcename(iparam))
                   call readf(f_t)
                   !
                   field%value(iparam) = f_t*unit_field
                   field%weight(iparam) = 0
                   !
                   if(nitems>=3) then
                     !
                     call readu(w)
                     !
                     if (trim(w(1:1))=="F") then 
                       !
                       field%weight(iparam) = 1.0_rk
                       !
                       if (nitems>=4) call readu(w)
                       !
                     elseif(trim(w(1:1))/="L") then
                       !
                       ! old input? 
                       !
                       field%weight(iparam) = f_t
                       read(w,*) field%value(iparam)
                       !
                       if (nitems>=4) call readu(w)
                       !
                     endif
                     !
                     if(trim(w(1:1))=="L".and.nitems>5) then
                       !
                       call readi(field%link(iparam)%iobject)
                       call readi(field%link(iparam)%ifield)
                       call readi(field%link(iparam)%iparam)
                       !
                       ! set the weight of the linked parameter to zero
                       !
                       field%weight(iparam) = 0
                       !
                     endif
                     !
                   endif 
                   !
                   job%total_parameters = job%total_parameters + 1
                   !
                 end select
                 !
              enddo
              !
              call readu(w)
              !
              if (iparam/=Nparam.or.(trim(w)/="".and.trim(w)/="END")) then
                 !
                 print "(2a,2i6)","wrong number of rows in section: ",trim(field%name),iparam,Nparam
                 call report("illegal number of rows in a section: "//trim(w),.true.)
                 !
              endif
                 !
            case default
                 !
                 call report ("Unrecognized unit name "//trim(w),.true.)
                 !
            end select
            !
            call read_line(eof,iut) ; if (eof) exit
            call readu(w)
          enddo
         !
       case("SYMGROUP","SYMMETRY","SYMM","SYM","SYM_GROUP") 
         !
         call readu(w)
         !
         job%symmetry = trim(w)
         !
         if (trim(job%symmetry)=="C") job%symmetry = "C(S)"
         !
         ! Initialize the group symmetry 
         !
         call SymmetryInitialize(job%symmetry)
         !
         symmetry_defined = .true.
         !
         allocate(job%isym_do(sym%Nrepresen),stat=alloc)
         if (alloc/=0)  stop 'input, isym_do - out of memory'
         !
         job%isym_do = .true.
         !
       case("INTENSITY")
         !
         ! skip if intensity NONE
         !
         if (Nitems>1) then
           call readu(w)
           if (trim(w)=="NONE") then
             do while (trim(w)/="".and.trim(w)/="END")
               call read_line(eof,iut) ; if (eof) exit
               call readu(w)
             enddo
             cycle
           endif
         endif
         !
         if (Nestates==0) then 
            !
            write (out,"('input: INTENSITY cannot appear before anypoten entries')") 
            stop 'input - INTENSITY defined before all poten entries'
            !
         endif 
         !
         if (.not.symmetry_defined) then 
            !
            write (out,"('input: INTENSITY cannot appear before symmetry is defined')") 
            stop 'input - INTENSITY defined befor symmetry'
            !
         endif 
         !
         allocate(intensity%gns(sym%Nrepresen),intensity%isym_pairs(sym%Nrepresen),stat=alloc)
         if (alloc/=0) stop 'input, intensity-arrays - out of memory'
         !
         ! defauls values
         !
         intensity%gns = 1
         forall(i=1:sym%Nrepresen) intensity%isym_pairs(i) = 1
         !intensity%v_low(1) = 0 ; intensity%v_low(2) = job%bset(:)%range(2)
         !intensity%v_upp(1) = 0 ; intensity%v_upp(2) = job%bset(:)%range(2)
         !
         !
         call read_line(eof,iut) ; if (eof) exit
         call readu(w)
         !
         do while (trim(w)/="".and.trim(w)/="END")
           !
           select case(w)
           !
           case('NONE','ABSORPTION','EMISSION','TM','DIPOLE-TM','RAMAN','POLARIZABILITY-TM','PARTFUNC')
             !
             intensity%action = trim(w)
             !
             if (trim(intensity%action)=='DIPOLE-TM') intensity%action = 'TM'
             !
             if (any(trim(intensity%action)==(/'TM','ABSORPTION','EMISSION','PARTFUNC'/))) then 
               !
               action%intensity = .true.
               intensity%do = .true.
               !
             endif
             !
           case('LINELIST')
             !
             call reada (intensity%linelist_file)
             !
           case('MATELEM')
             !
             intensity%matelem = .true.
             !
           case('THRESH_INTES','THRESH_TM','THRESH-INTES')
             !
             call readf(intensity%threshold%intensity)
             !
           case('THRESH_LINE','THRESH_LINESTRENGHT','THRESH_EINSTEIN','THRESH-EINSTEIN')
             !
             call readf(intensity%threshold%linestrength)
             !
           case('THRESH_COEFF','THRESH_COEFFICIENTS')
             !
             call readf(intensity%threshold%coeff)
             !
           case('TEMPERATURE')
             !
             call readf(intensity%temperature)
             !
           case('QSTAT','PARTITION','PART_FUNC','Q','PART-FUNC')
             !
             call readf(intensity%part_func)
             !
           case('GNS')
             !
             i = 0
             !
             do while (item<Nitems.and.i<sym%Nrepresen)
               !
               i = i + 1
               call readf(intensity%gns(i))
               if (intensity%gns(i)<small_) job%isym_do(i) = .false.
               !
             enddo
             !
             if (i/=sym%Nrepresen.and.sym%Nrepresen==2) then 
               !
               intensity%gns(2) = intensity%gns(1)
               !
             elseif (i/=sym%Nrepresen.and.sym%Nrepresen==2) then
               !
               write (out,"('input: illegal number entries in gns: ',i8,' /= ',i8)") i,sym%Nrepresen
               stop 'input - illegal number entries in gns'
               !
             endif 
             !
           case('SELECTION','SELECTION_RULES','SELECT','PAIRS')
             !
             i = 0
             !
             do while (trim(w)/="".and.i<sym%Nrepresen)
               !
               i = i + 1
               !
               call readi(intensity%isym_pairs(i))
               !
             enddo
             !
             if (i/=sym%Nrepresen) then 
               !
               write (out,"('input: illegal number entries in SELECTION: ',i8,' /= ',i8)") i,sym%Nrepresen
               stop 'input - illegal number entries in SELECTION'
               !
             endif 
             !
           case('ZPE')
             !
             call readf(intensity%zpe)
             job%zpe = intensity%zpe
             !
           case('J','JLIST','JROT')
             !
             call readf(intensity%j(1))
             !
             if (nitems>3) then 
               call readu(w)
               if (trim(w)/="-") call report ("Unrecognized delimeter, can be comma or dash "//trim(w),.true.)
             endif
             !
             call readf(intensity%j(2))
             !
           case('FREQ-WINDOW','FREQ','NU','FREQUENCY')
             !
             call readf(intensity%freq_window(1))
             call readf(intensity%freq_window(2))
             !
             if (intensity%freq_window(1)<small_) intensity%freq_window(1) = -small_ 
             !
           case('ENERGY')
             !
             call readu(w)
             !
             do while (trim(w)/="")
                !
                select case(w)
                !
                case("LOWER","LOW","L")
                  !
                  call readf(intensity%erange_low(1))
                  call readf(intensity%erange_low(2))
                  !
                  if (intensity%erange_low(1)<small_) intensity%erange_low(1)= -small_ 
                  !
                case("UPPER","UPP","UP","U")
                  !
                  call readf(intensity%erange_upp(1))
                  call readf(intensity%erange_upp(2))
                  !
                  if (intensity%erange_upp(1)<small_) intensity%erange_upp(1)=-small_ 
                  !
                end select 
                !
                call readu(w)
                !
             enddo 
             !
           !case('LOWER','LOW','L')
           !  !
           !  call readu(w)
           !  !
           !  call input_quanta(w,intensity%lower)
           !  !
           !case('UPPER','UP','U')
           !  !
           !  call readu(w)
           !  !
           !  call input_quanta(w,intensity%upper)
           !  !
           case default
             !
             call report ("Unrecognized unit name "//trim(w),.true.)
             !
           end select 
           !
           call read_line(eof,iut) ; if (eof) exit
           call readu(w)
           !
         enddo
         !
         if (trim(intensity%action) == 'ABSORPTION'.or.trim(intensity%action) == 'EMISSION') then 
           !
           ! define the selection pairs by gns if not yet defined
           !
           i_t = 0
           !
           do i = 1,sym%Nrepresen
             !
             if (intensity%isym_pairs(i)/=0) cycle
             !
             do j = 1,sym%Nrepresen
               !
               if (i/=j.and.intensity%isym_pairs(j)==0.and.intensity%gns(i)==intensity%gns(j)) then 
                 !
                 i_t = i_t + 1
                 !
                 intensity%isym_pairs(i) = i_t
                 intensity%isym_pairs(j) = i_t
                 !
               endif 
               !
             enddo
             !
           enddo
           !
         endif 
         !
       case default
         call report ("Principal keyword "//trim(w)//" not recognized",.true.)
       end select
       !
    end do
    !
    Nestates = iobject(1)
    !
    Nspinorbits = iso
    Ndipoles = idip
    Nlxly = ilxly
    Nl2   = il2
    Nabi  = 0
    Nss   = iss
    Nsso  = isso
    Nbobrot  = ibobrot
    Nsr = isr
    Ndiabatic = idiab
    Nlambdaopq = iobject(10)
    Nlambdap2q = iobject(11)
    Nlambdaq = iobject(12)
    !
    ! create a map with field distribution
    !
    do i = 1,Nobjects-2
      fieldmap(i)%Nfields = iobject(i)
    enddo
    !
    !fieldmap(1)%Nfields = Nestates
    !fieldmap(2)%Nfields = Nspinorbits
    !fieldmap(3)%Nfields = Nl2
    !fieldmap(4)%Nfields = Nlxly
    !fieldmap(5)%Nfields = Nss
    !fieldmap(6)%Nfields = Nsso
    !fieldmap(7)%Nfields = Nbobrot
    !fieldmap(8)%Nfields = Nsr
    !fieldmap(9)%Nfields = Ndiabatic
    !fieldmap(10)%Nfields = iobject(10)
    !
    fieldmap(Nobjects-2)%Nfields = Nabi
    fieldmap(Nobjects-1)%Nfields = 1  ! Brot
    fieldmap(Nobjects)%Nfields = Ndipoles
    !
    Ntotalfields = Nestates+Nspinorbits+NL2+NLxLy+Nss+Nsso+Nbobrot+Nsr+Ndiabatic+iobject(10)
    !
    Ntotalfields = sum(iobject(1:Nobjects-3))
    !
    ! check if all abinitio fields are initialized. If not we need to make dummy abinitio fields;
    ! we also check whether not all fields are given on a grid and thus can be varied.
    !
    !if (action%fitting .eqv. .true.) then
      !
      Nabi = Ntotalfields
      fieldmap(Nobjects-2)%Nfields = Nabi
      !
      ! we also check whether not all fields are given on a grid and thus can be varied.
      !
      allgrids = .true.
      !
      iabi = 0
      !
      do iobj = 1,Nobjects-3
        !
        do iterm = 1,fieldmap(iobj)%Nfields
          !
          select case (iobj)
          case (1)
            field => poten(iterm)
          case (2)
            field => spinorbit(iterm)
          case (3)
            field => l2(iterm)
          case (4)
            field => lxly(iterm)
          case (5)
            field => spinspin(iterm)
          case (6)
            field => spinspino(iterm)
          case (7)
            field => bobrot(iterm)
          case (8)
            field => spinrot(iterm)
          case (9)
            field => diabatic(iterm)
          case (10)
            field => lambdaopq(iterm)
          case (11)
            field => lambdap2q(iterm)
          case (12)
            field => lambdaq(iterm)
          case (Nobjects-2)
            field => abinitio(iterm)
          case default
             print "(a,i0)", "iobject = ",iobj
             stop "illegal iobject  "
          end select
          !
          iabi = iabi + 1
          !
          if (trim(field%type)/="GRID") allgrids = .false.
          !
          !field => abinitio(iabi)
          !
          if (.not.associated(abinitio(iabi)%value)) then
            !
            Nparam = 1 ; abinitio(iabi)%Nterms = 0
            !
            allocate(abinitio(iabi)%value(Nparam),abinitio(iabi)%forcename(Nparam),abinitio(iabi)%grid(Nparam), & 
                     abinitio(iabi)%weight(Nparam),stat=alloc)
            call ArrayStart(trim(abinitio(iabi)%type),alloc,Nparam,kind(abinitio(iabi)%value))
            call ArrayStart(trim(abinitio(iabi)%type),alloc,Nparam,kind(abinitio(iabi)%grid))
            call ArrayStart(trim(abinitio(iabi)%type),alloc,Nparam,kind(abinitio(iabi)%weight))
            !
            abinitio(iabi)%value = 0
            abinitio(iabi)%grid = 1.0_rk
            abinitio(iabi)%weight = 0
            abinitio(iabi)%type = 'DUMMY'  ! dummy field
            abinitio(iabi)%name    = field%name
            abinitio(iabi)%spini   = field%spini
            abinitio(iabi)%spinj   = field%spinj
            abinitio(iabi)%sigmai  = field%sigmai
            abinitio(iabi)%sigmaj  = field%sigmaj
            abinitio(iabi)%multi   = field%multi
            abinitio(iabi)%omega   = field%omega
            abinitio(iabi)%lambda  = field%lambda
            abinitio(iabi)%lambdaj = field%lambdaj
            !
          endif
          !
        enddo
      enddo
      !
      if (allgrids.and.action%fitting) then
        call report ("Fitting is not possible: No field of not the GRID-type!",.true.)
      endif 
      !
    !endif
    !
    !if (Nabi>Ntotalfields) then
    !    print "(2a,i4,a,i6)",trim(w),": Number of ab initio fields ",iabi," exceeds the total number of fields ",Ntotalfields
    !    call report ("Too many ab initio fields given in the input for"//trim(w),.true.)
    !endif
    !
    !
    ! check the number of total states
    !
    if (iobject(1)/=nestates) then
      write(out,'("The number of states required ",i8," is inconcistent (smaller) with the number of PECs ",i8," included")') & 
                 nestates,iobject(1)
      stop "Illegal number of states: ipo/=nestates"
    endif
    !
    ! find lowest Jmin allowed by the spin and lambda
    ! this is done by computing all possible |Omegas| = | Lambda + Sigma |
    ! we assume Jmin=min( Omegas )
    !
    !lambda_ = 100
    !spin_ = lambda_
    omega_ = 100000._rk

    do istate=1,Nestates
      spin_   = poten(istate)%spini
      lambda_ = poten(istate)%lambda
      !do Sigma_=-Spin_,0
      ! omega_=min(omega_,abs(lambda_+sigma_))
      !enddo
      do i=0, nint( 2._rk * spin_ )
       sigma_=-spin_ + real(i, rk)
       omega_=min(omega_,abs(lambda_+sigma_))
      end do
      !
      !if (poten(istate)%lambda<lambda_) then
      !  lambda_ = poten(istate)%lambda
      !  spin_ = poten(istate)%spini
      !endif
      !
    enddo
    !
    !jmin_ = abs( real(lambda_) ) ; 
    !if (.not.integer_spin) jmin_ = abs( real(lambda_)-0.5_rk )
    !
    !jmin_ = abs( real(lambda_)-abs(spin_) ) ! ; if (.not.integer_spin) jmin_ = jmin_-0.5_rk
    !
    !if (.not.integer_spin) jmin_ = abs(jmin_- 0.5_rk)
    !
    jmin = omega_
    if (jmax<jmin) jmax = jmin
    !
    ! check the L2 terms:
    !
    !if (Nl2>nestates) then
    !  write(out,'("The number of L2 components ",i8," is inconsistent with the number of electronic states ",i8," included")') & 
    !              Nl2,nestates
    !  stop "Illegal number of L2 components: Nl2>nestates"
    !endif
    !
    !do istate = 1,Nl2
    !  if (L2(il2)%iref/=poten(L2(il2)%istate)%iref) then
    !    write(out,'("For the state ",i4," the reference number of L2  = ",i8," is inconsistent with the ref-number of the" &
    !                 // " electronic states = ",i8)') istate,L2(istate)%iref,poten(istate)%iref
    !    stop "Illegal ref-number of L2 components: il2-ref/=ipot-ref"
    !  endif
    !enddo
    !
    write(out,"('...done!'/)")

  contains
    !
    subroutine input_quanta(w,field)
      !
      character(len=cl),intent(in) :: w
      type(quantaT),intent(inout)  :: field
      
      do while (trim(w)/="")
        !      
        select case (w)
          !
        case("J")
          !
          call readf(field%jrot)
          !
        case("OMEGA")
          !
          call readf(field%omega)
          !
        case("V")
          !
          call readi(field%v)
          !
        case("LAMBDA")
          !
          call readi(field%ilambda)
          !if (nitems>2) call readi(field%ilambdaj)
          !
        case("STATE")
          !
          call readi(field%istate)
          !
        case("SIGMA")
          !
          call readf(field%sigma)
          !if (nitems>2) call readf(field%sigmaj)
          !
        case("SPIN")
          !
          call readf(field%spin)
          !
          !if (nitems>2) call readf(field%spinj)
          !
          !if (mod(nint(2.0_rk*field%spini+1.0_rk),2)==0.and.integer_spin) then
          !  call report("The multiplicity of j-s in J_lits are inconcistent with the SPIN of the field defined at:",.true.)
          !endif
          !
        end select
        !
        call readu(w)
        !
     enddo 
     !
    end subroutine input_quanta


    !
  end subroutine ReadInput




  !
  subroutine define_quanta_bookkeeping(iverbose,jval,Nestates,Nlambdasigmas)
    !
    integer(ik),intent(in) :: iverbose
    real(rk),intent(in)    :: jval
    integer(ik),intent(in) :: nestates
    integer(ik),intent(out) :: Nlambdasigmas ! to count states with different lambda/sigma
    integer(ik) :: ilevel,itau,ilambda,nlevels,multi_max,imulti,istate,multi,alloc,taumax
    real(rk)    :: sigma,omega
    !
    if (iverbose>=4) call TimerStart('Define quanta')
    !
    ilevel = 0
    multi_max = 1
    !
    ! count states
    !
    do istate = 1,nestates
      !
      multi_max = max(poten(istate)%multi,multi_max)
      multi = poten(istate)%multi
      !
      taumax = 1
      if (poten(istate)%lambda==0) taumax = 0
      !
      do itau = 0,taumax
        ilambda = (-1)**itau*poten(istate)%lambda
        !
        sigma = -poten(istate)%spini
        do imulti = 1,multi
          !
          omega = real(ilambda,rk)+sigma
          !
          if (nint(2.0_rk*abs(omega))<=nint(2.0_rk*jval)) then
            ilevel = ilevel + 1
          endif
          sigma = sigma + 1.0_rk
          !
        enddo
        !
      enddo
      !
    enddo
    !
    nlevels = ilevel
    !
    if (allocated(iquanta2ilevel)) then
       deallocate(quanta)
       deallocate(iquanta2ilevel)
       call ArrayStop('quanta')
    endif
    !
    allocate(quanta(nlevels),stat=alloc)
    allocate(iquanta2ilevel(Nestates,0:1,multi_max),stat=alloc)
    call ArrayStart('quanta',alloc,size(iquanta2ilevel),kind(iquanta2ilevel))
    iquanta2ilevel = 1e4
    !
    ! the total number of the spin-lambda-electronic states
    !
    Nlambdasigmas = nlevels
    !
    if (iverbose>=4) write(out,'("The total number sigma/lambda states (size of the sigma-lambda submatrix) = ",i0)') Nlambdasigmas
    !
    ! assign quanta (rotation-spin-sigma)
    !
    ilevel = 0
    !
    if (iverbose>=4) write(out,'(/"Sigma-Lambda basis set:")')
    if (iverbose>=4) write(out,'("     i     jrot  state   spin    sigma lambda   omega")')
    !
    do istate = 1,nestates
      multi = poten(istate)%multi
      !
      taumax = 1
      if (poten(istate)%lambda==0) taumax = 0
      do itau = 0,taumax
        ilambda = (-1)**itau*poten(istate)%lambda
        !
        sigma = -poten(istate)%spini
        !
        do imulti = 1,multi
          !
          omega = real(ilambda,rk)+sigma
          !
          if (nint(2.0_rk*abs(omega))<=nint(2.0_rk*jval)) then
            !
            ilevel = ilevel + 1
            !
            quanta(ilevel)%spin = poten(istate)%spini
            quanta(ilevel)%istate = istate
            quanta(ilevel)%sigma = sigma
            quanta(ilevel)%imulti = imulti
            quanta(ilevel)%ilambda = ilambda
            quanta(ilevel)%omega = real(ilambda,rk)+sigma
            iquanta2ilevel(istate,itau,imulti) = ilevel
            !
            ! print out quanta
            !
            if (iverbose>=4) write(out,'(i6,1x,f8.1,1x,i4,1x,f8.1,1x,f8.1,1x,i4,1x,f8.1,3x,a)') & 
                             ilevel,jval,istate,quanta(ilevel)%spin,sigma,ilambda,omega,trim(poten(istate)%name)
            !
          endif
          !
          sigma = sigma + 1.0_rk
          !
        enddo
        !
      enddo
    enddo
    !
    if (iverbose>=4) call TimerStop('Define quanta')
    !
  end subroutine define_quanta_bookkeeping
  !

subroutine map_fields_onto_grid(iverbose)
     !
     use functions,only : define_analytical_field
     !
     character(len=130)     :: my_fmt  !text variable containing formats for reads/writes
     ! 
     integer(ik),intent(in) :: iverbose
     !
     integer(ik)             :: ngrid,alloc,j,nsub,Nmax,iterm,nterms,i,ipotmin=1,istate,jstate,itotal
     integer(ik)             :: ifterm,iobject,ifield
     real(rk)                :: rmin, rmax, re, alpha, h,sc,h12,scale,check_ai
     real(rk),allocatable    :: f(:)
     !
     integer             :: np   ! tmp variable for extrapolation
     real(kind=rk)       :: x1, x2, y1, y2, aa, bb ! tmp variables used for extrapolation
     !
     real(rk),allocatable    :: spline_wk_vec(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: spline_wk_vec_B(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: spline_wk_vec_C(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: spline_wk_vec_D(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: spline_wk_vec_E(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: spline_wk_vec_F(:) ! working vector needed for spline interpolation
     real(rk),allocatable    :: xx(:), yy(:), ww(:)! tmp vectors for extrapolation
     real(rk) :: yp1, ypn
     !
     type(fieldT),pointer      :: field
     !
     ngrid = grid%npoints
     !
     if (allocated(r)) then
       deallocate(r,z,d2dr,r2sc)
       call ArrayStop('r-field')
     endif
     !
     !
     if (associated(grid%r)) then
       deallocate(grid%r)
       call ArrayStop('grid%r')
     endif
     !
     allocate(r(ngrid),z(ngrid),f(ngrid),d2dr(ngrid),r2sc(ngrid),grid%r(ngrid),stat=alloc)
     call ArrayStart('grid%r',alloc,ngrid,kind(grid%r))
     call ArrayStart('r-field',alloc,ngrid,kind(r))
     call ArrayStart('f-field',alloc,ngrid,kind(f))
     call ArrayStart('r-field',alloc,ngrid,kind(z))
     call ArrayStart('r-field',alloc,ngrid,kind(d2dr))
     call ArrayStart('r-field',alloc,ngrid,kind(r2sc))
     !
     rmin = grid%rmin
     rmax = grid%rmax
     !
     nsub = grid%nsub
     alpha = grid%alpha
     re = grid%re
     !
     ! mapping grid
     !
     ! reduced mass in amu (i.e., Daltons)
     !
     amass = m1*m2/(m1+m2)
     !
     if (iverbose>=4) write(out, '(a,f25.10,5x,a,/)') 'Reduced mass is ', amass, 'atomic mass units (Daltons)'
     !
     scale = amass/aston
     !
     if (iverbose>=4) call TimerStart('Define grid')
     !
     call gridred(nsub,alpha,re,ngrid,rmin,rmax,h,r,z,f,iverbose)
     !
     grid%r = r
     !
     if (iverbose>=4) call TimerStop('Define grid')
     !
     hstep = h
     !
     h12 = 12.0_rk*h**2
     sc  = h12*scale
     !
     ! For uniformly spaced grid z(j)= 1 ; f(j) = 0
     do j = 1, ngrid
        r2sc(j)= scale*r(j)*r(j)
        d2dr(j) = 30.0_rk*z(j)*z(j) - h12*f(j)
     enddo
     !
     deallocate(f)
     call ArrayStop('f-field')
     !
     ! generate grid-representaion for the all type of of the hamiltonian fields
     !
     if (iverbose>=4) call TimerStart('Grid representaions')
     !
     if (iverbose>=3) write(out,'("Generate a grid representation for all Hamiltonian terms")')
     !
     ! in case of fitting we will need this object to store the parameters to refine
     !
     if (action%fitting) then
       !
       itotal = 0
       ifterm = 0
       !
     endif
     !
     object_loop: do iobject = 1,Nobjects
        !
        Nmax = fieldmap(iobject)%Nfields
        !
        ! each field type consists of Nmax terms
        !
        do iterm = 1,Nmax
          !
          select case (iobject)
          case (1)
            field => poten(iterm)
          case (2)
            field => spinorbit(iterm)
          case (3)
            field => l2(iterm)
          case (4)
            field => lxly(iterm)
          case (5)
            field => spinspin(iterm)
          case (6)
            field => spinspino(iterm)
          case (7)
            field => bobrot(iterm)
          case (8)
            field => spinrot(iterm)
          case (9)
            field => diabatic(iterm)
          case (10)
            field => lambdaopq(iterm)
          case (11)
            field => lambdap2q(iterm)
          case (12)
            field => lambdaq(iterm)
          case (Nobjects-2)
            field => abinitio(iterm)
          case (Nobjects-1)
            cycle
          case (Nobjects)
            field => dipoletm(iterm)
          case default
             print "(a,i0)", "iobject = ",iobject
             stop "illegal iobject  "
          end select
          !
          if (.not.gridvalue_allocated) then 
            !
            allocate(field%gridvalue(ngrid),stat=alloc)
            call ArrayStart(trim(field%type),alloc,ngrid,kind(field%gridvalue))
            !
          endif
          !
          select case(trim(field%type))
          !
          case("GRID")
            !
            nterms = field%Nterms
            !
            ! Lorenzo Lodi, 13 February 2014
            ! This section will add extrapolated points at short and long bond lengths
            ! for tabulated `GRID' functions
            if( field%grid(1) > rmin) then
               if (iverbose>=4) write(out, '(/,A)') 'Extrapolating at short bond length curve ' // trim(field%name) // &
                                 ' (class ' // trim(field%class) // ')'
         
         
                 np = 20              ! I always add `np' short bond length guide points
                ! I go one step `beyond' rmin to minimize interpolating artifacts at the end of the interval
         
                 x1=field%grid(1)  ; y1 =field%value(1)
                 x2=field%grid(2)  ; y2 =field%value(2)
                 allocate( xx(nterms+np), yy(nterms+np),ww(nterms+np) )
                 xx=0._rk
                 yy=0._rk
                 do i=1, np
                    xx(i) = rmin + (field%grid(1)-rmin)*real(i-2,rk) / real( np-1, rk)
                 enddo
                 !
               select case(field%class)
                 !
               case ("POTEN")
                 if (iverbose>=4) write(out, '(A, I20)') 'Using A + B/r extrapolation; points added = ', np
                 bb = -x1*x2*(y1-y2)/(x1-x2)
                 aa = y1 - bb/x1
                 do i=1, np
                    yy(i) = aa + bb/xx(i)
                 enddo
                 !
               case ("DIPOLE")
                 if (iverbose>=4) write(out, '(A, I20)') 'Using A*r + B*r^2 extrapolation; points added = ', np
                 bb = (x2*y1- x1*y2) / (x1*x2 *(x1-x2) )
                 aa = (-bb*x1**2 + y1 ) / x1
                 do i=1, np
                    yy(i) = aa*xx(i) + bb*xx(i)**2
                 enddo
                 !
               case default  ! linear extrapolation using the first two points to r = rmin - 1/(np-1)
                 if (iverbose>=4) write(out, '(A, I20)') 'Using linear extrapolation; points added = ', np
                 do i=1, np
                      yy(i) = y1 + (xx(i)-x1) * (y1-y2)/(x1-x2)
                 enddo
               end select
               !
               do i=np+1, np+nterms
                  xx(i) =  field%grid(i-np)
                  yy(i) =  field%value(i-np)
               enddo
               !
               ww(np+1:) = field%weight(1:) ; ww(1:np) = 0
               nterms = np+nterms
               field%Nterms = nterms
               deallocate(field%grid, field%value, field%weight, field%forcename)
               allocate(field%value(nterms),field%forcename(nterms),field%grid(nterms),field%weight(nterms),stat=alloc)
               field%grid  = xx
               field%value = yy
               field%forcename= 'dummy'
               field%weight = ww
               deallocate(xx, yy, ww)
               !
            endif
            !*************end of short bond length extrapolation **********************************************
            nterms = field%Nterms
            if( field%grid(nterms) < rmax) then
               if (iverbose>=4) write(out, '(/,A)') 'Extrapolating at long bond length curve ' // trim(field%name) // &
                                ' (class ' // trim(field%class) // ')'
               !
               np = 20    ! I always add `np' long bond length guide points
               ! I go one step `beyond' rmax to minimize interpolating artifacts at the end of the interval
               !
               x1=field%grid(nterms-1)  ; y1 =field%value(nterms-1)
               x2=field%grid(nterms)    ; y2 =field%value(nterms)
               allocate( xx(nterms+np), yy(nterms+np),ww(nterms+np) )
               !
               xx=0._rk
               yy=0._rk
               do i=1, nterms
                  xx(i) =  field%grid(i)
                  yy(i) =  field%value(i)
               enddo
               !
               do i=nterms+1, nterms+np
                  xx(i) = field%grid(nterms) + (rmax-field%grid(nterms))*real(i-nterms,rk) / real( np-1, rk)
               enddo
               !
               select case(field%class)
         
               case ("POTEN")
                 if (iverbose>=4) write(out, '(A, I20)') 'Using De + A/r^6 extrapolation; points added = ', np
                 bb = (x1*x2)**6 * (y2-y1) / (x1**6 - x2**6)
                 aa = y1 - bb/x1**6
                 !       write(out, '(A, 2F20.4)') 'Dissociation set to = ', aa !, bb
                 do i=nterms+1,nterms+np
                    yy(i) = aa + bb / xx(i)**6
                 enddo
                 !
               case ("DIPOLE")
                 if (iverbose>=4) write(out, '(A, I20)') 'Using A/r^2 + B/r^3 extrapolation; points added = ', np
                 bb = x1*x2*(x1**2 * y1 - x2**2 * y2)/(x2-x1)
                 aa = (y1*x1**3 - bb)/x1
                 do i=nterms+1,nterms+np
                    yy(i) = aa/xx(i)**2 + bb / xx(i)**3
                 enddo
                 !
               case default  ! extrapolation using the last two points
                 if (iverbose>=4) write(out, '(A, I20)') 'Using linear extrapolation; points added = ', np
                 do i=nterms+1,nterms+np
                      yy(i) = y1 + (xx(i)-x1) * (y1-y2)/(x1-x2)
                  enddo
               end select
               !
               ww(1:nterms) = field%weight(1:nterms) ; ww(nterms+1:) = 0
               nterms = np+nterms
               field%Nterms = nterms
               deallocate(field%grid, field%value, field%weight, field%forcename)
               allocate(field%value(nterms),field%forcename(nterms),field%grid(nterms),field%weight(nterms),stat=alloc)
               field%grid  = xx
               field%value = yy
               field%forcename= 'dummy'
               field%weight = ww
               deallocate(xx, yy, ww)
            endif
            !
            !*************end of long bond length extrapolation **********************************************
            !
            ! build spline interpolant
            select case (field%interpolation_type)
              !
            case default
               write(out,"(a)") "Unrecognized interpolation type ", field%interpolation_type
               stop "illegal iobject"
               ! -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- .
            case("CUBICSPLINES")  ! cubic natural spline
               !
               if (iverbose>=6) write(out, '(A, I20)') 'Interpolating with cubic natural splines'
               allocate(spline_wk_vec(nterms),stat=alloc)
               call ArrayStart('spline_wk_vec-field',alloc,ngrid,kind(spline_wk_vec))
               !
               yp1= 0._rk ; ypn =0._rk  ! 1nd derivatives at the first and last point (ignored)
               call spline(field%grid,field%value,field%Nterms,yp1,ypn,spline_wk_vec)
               !
               !$omp parallel do private(i) schedule(guided)
               do i=1,ngrid
                ! evaluate spline interpolant
                call splint(field%grid,field%value,spline_wk_vec,field%Nterms,r(i),field%gridvalue(i))
               enddo
               !$omp end parallel do
               !
               deallocate(spline_wk_vec)
               call ArrayStop('spline_wk_vec-field')
               !
               ! -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- .
            case("QUINTICSPLINES")  ! quintic spline
               !
               if (iverbose>=6) write(out, '(A, I20)') 'Interpolating with quintic splines'
               nterms=field%Nterms
               allocate(spline_wk_vec_B(nterms),stat=alloc); call ArrayStart('spline_wk_vec_B',alloc,nterms,kind(spline_wk_vec))
               allocate(spline_wk_vec_C(nterms),stat=alloc); call ArrayStart('spline_wk_vec_C',alloc,nterms,kind(spline_wk_vec))
               allocate(spline_wk_vec_D(nterms),stat=alloc); call ArrayStart('spline_wk_vec_D',alloc,nterms,kind(spline_wk_vec))
               allocate(spline_wk_vec_E(nterms),stat=alloc); call ArrayStart('spline_wk_vec_E',alloc,nterms,kind(spline_wk_vec))
               allocate(spline_wk_vec_F(nterms),stat=alloc); call ArrayStart('spline_wk_vec_F',alloc,nterms,kind(spline_wk_vec))
               !
               call QUINAT(nterms, field%grid,field%value, spline_wk_vec_B, spline_wk_vec_C, &
                                            spline_wk_vec_D, spline_wk_vec_E, spline_wk_vec_F)
               !
               !$omp parallel do private(i) schedule(guided)
               do i=1,ngrid    ! evaluate spline interpolant
!                 call splint(field%grid,field%value,spline_wk_vec,field%Nterms,r(i),field%gridvalue(i))

                  call splint_quint(field%grid,field%value,nterms,r(i),field%gridvalue(i), spline_wk_vec_B, &
                                     spline_wk_vec_C, spline_wk_vec_D, spline_wk_vec_E, spline_wk_vec_F)
               enddo
               !$omp end parallel do
               !
               deallocate(spline_wk_vec_B) ; call ArrayStop('spline_wk_vec_B')
               deallocate(spline_wk_vec_C) ; call ArrayStop('spline_wk_vec_C')
               deallocate(spline_wk_vec_D) ; call ArrayStop('spline_wk_vec_D')
               deallocate(spline_wk_vec_E) ; call ArrayStop('spline_wk_vec_E')
               deallocate(spline_wk_vec_F) ; call ArrayStop('spline_wk_vec_F')
               ! -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- . -- .
               !
            end select
            !
            ! for dummy fields not used in fittings
            !
          case("DUMMY")
            !
            nterms = field%Nterms
            field%gridvalue = 0._rk
            !
          case default
            !
            call define_analytical_field(field%type,field%analytical_field)
            !
            !$omp parallel do private(i) schedule(guided)
            do i=1,ngrid
              !
              field%gridvalue(i) = field%analytical_field(r(i),field%value)
              !
            enddo
            !$omp end parallel do
            !
            ! counting the total number of parameters when the fitting is on
            !
            if (action%fitting) then
              itotal = itotal + field%Nterms
            endif
            !
          end select
          !
          field%gridvalue =  field%gridvalue*field%factor
          !
        enddo
        !
     enddo object_loop
     !
     ! change the status of  gridvalue_allocated to true (allocated)
     ! to prevent reallocation next time this subroutine is called (e.g. from the refinement)
     gridvalue_allocated = .true.
     !
     ! Now morph the objects by applying the morphing function to the corresponding ab initio field if neccessary
     !
     ifield = 0 
     
     object_loop2: do iobject = 1,Nobjects
        !
        Nmax = fieldmap(iobject)%Nfields
        !
        ! each field type constits of Nmax terms
        !
        do iterm = 1,Nmax
          !
          select case (iobject)
          case (1)
            field => poten(iterm)
          case (2)
            field => spinorbit(iterm)
          case (3)
            field => l2(iterm)
          case (4)
            field => lxly(iterm)
          case (5)
            field => spinspin(iterm)
          case (6)
            field => spinspino(iterm)
          case (7)
            field => bobrot(iterm)
          case (8)
            field => spinrot(iterm)
          case (9)
            field => diabatic(iterm)
          case (10)
            field => lambdaopq(iterm)
          case (11)
            field => lambdap2q(iterm)
          case (12)
            field => lambdaq(iterm)
          case (Nobjects-2)
            !
            ! no morphing for ab initio 
            cycle
            !
          case (Nobjects-1)
            !
            ! no morphing for Brot 
            cycle
            !
          case (Nobjects)
            field => dipoletm(iterm)
          case default
             print "(a,i0)", "iobject = ",iobject
             stop "illegal iobject  "
          end select
          !
          ifield = ifield + 1
          !
          ! Introduce morphing
          !
          if (field%morphing) then
            !
            ! check if ai field was defined 
            !
            check_ai = sum((abinitio(ifield)%gridvalue)**2)
            !
            if (check_ai<small_) then 
              !
              write(out,"('Cooresposnding ab initio field must be defined when using MORPHING for ',a)") field%name
              stop 'ab initio field is undefined while using MOPRHING'
              !
            endif
            ! 
            field%gridvalue = field%gridvalue*abinitio(ifield)%gridvalue
          endif
          !
          ! transform from the MOLRPO to Duo representation
          !
          if (field%molpro) then
            !
            call molpro_duo(field)
            !
          endif
          !
        enddo
        !
     enddo object_loop2
     !
     if (action%fitting) then
       fitting%parmax = itotal
     endif
     !
     if (iverbose>=3) write(out,'("...done!"/)')
     !
     if (iverbose>=4) call TimerStop('Grid representaions')
     !
     ! find the minimum of the lowest PEC
     !
     ipotmin = minloc(poten(1)%gridvalue,dim=1) ; job%potmin = poten(1)%gridvalue(ipotmin)
     !
     ! shift PECs relative to the ground electronic state minimum
     do istate=1,Nestates
       poten(istate)%gridvalue(:) = poten(istate)%gridvalue(:)-job%potmin
     enddo
     !
     call check_and_print_field(Nestates,iverbose,poten,"Potential functions:")
     !
     call check_and_print_coupling(Nspinorbits,iverbose,spinorbit,"Spin-Orbit:")
     call check_and_print_coupling(Nlxly,      iverbose,lxly,     "<L+> functions:")
     call check_and_print_coupling(NL2,        iverbose,l2,       "<L**2> functions:")
     call check_and_print_coupling(Nss,        iverbose,spinspin, "Spin-spin functions:")
     call check_and_print_coupling(Nsso,       iverbose,spinspino,"Spin-spin-o (non-diagonal) functions:")
     call check_and_print_coupling(Nsr,        iverbose,spinrot,  "Spin-rotation functions:")
     call check_and_print_coupling(Nbobrot,    iverbose,bobrot,   "Bob-Rot centrifugal functions:")
     call check_and_print_coupling(Ndiabatic,  iverbose,diabatic, "Diabatic functions:")
     call check_and_print_coupling(Nlambdaopq, iverbose,lambdaopq,  "Lambda-opq:")
     call check_and_print_coupling(Nlambdap2q, iverbose,lambdap2q,  "Lambda-p2q:")
     call check_and_print_coupling(Nlambdaq,   iverbose,lambdaq,  "Lambda-q:")
     call check_and_print_coupling(Ndipoles,   iverbose,dipoletm, "Dipole moment functions:")
     !
   contains 
     !
     subroutine molpro_duo(field)
        !
        use lapack,only : lapack_zheev     
        !
        type(fieldT),intent(inout) :: field
        integer(ik) :: ix_lz_y,jx_lz_y,iroot,jroot,il_temp
        complex(rk) :: a(2,2),b(2,2),coupling(2,2),f_t(2,2),b0(2,2),c
        real(rk)    :: lambda_i(2),lambda_j(2)
            !
            ix_lz_y = field%ix_lz_y
            jx_lz_y = field%jx_lz_y
            !
            a = 0 ; b = 0
            !
            a(1,1) =  cmplx(1.0_rk,0.0_rk)
            b(1,1) =  cmplx(1.0_rk,0.0_rk)
            a(2,2) =  cmplx(1.0_rk,0.0_rk)
            b(2,2) =  cmplx(1.0_rk,0.0_rk)
            !
            iroot = 1
            jroot = 1
            !
            if (ix_lz_y/=0) then
              a = 0 
              a(1,2) = cmplx(0.0_rk,ix_lz_y)
              a(2,1) = cmplx(0.0_rk,-ix_lz_y)
              !
              call lapack_zheev(a,lambda_i)
              !
              ! swap to have the first root positive 
              !
              f_t = a
              a(:,1) = f_t(:,2)
              a(:,2) = f_t(:,1)
              !
              il_temp = lambda_i(2)
              lambda_i(2) = lambda_i(1)
              lambda_i(1) = il_temp
              !
              field%lambda = nint(lambda_i(1))
              !
              a = a*cmplx(0.0_rk,1.0_rk)
              !
            elseif (poten(field%istate)%parity%pm==-1) then 
              !
              a(1,1) =  cmplx(0.0_rk,1.0_rk)
              !
            endif
            !
            if (jx_lz_y/=0) then
              b = 0 
              b(1,2) = cmplx(0.0_rk,jx_lz_y)
              b(2,1) = cmplx(0.0_rk,-jx_lz_y)
              !
              b0 = b
              !
              call lapack_zheev(b,lambda_j)
              !
              ! swap to have the first root positive 
              !
              f_t = b
              b(:,1) = f_t(:,2)
              b(:,2) = f_t(:,1)
              !
              il_temp = lambda_j(2)
              lambda_j(2) = lambda_j(1)
              lambda_j(1) = il_temp
              !
              field%lambdaj = nint(lambda_j(1))
              !
              b = b*cmplx(0.0_rk,1.0_rk)
              !
              f_t = matmul( conjg(transpose(b)),matmul(b0,(b)) )
              !
            elseif (poten(field%jstate)%parity%pm==-1) then 
              !
              b(1,1) =  cmplx(0.0_rk,1.0_rk)
              !
            endif
            !
            ! Check the selection rules
            select case(trim(field%class))
              !
            case('SPINORBIT')
              !
              if ((nint(field%sigmaj-field%sigmai))/=(field%lambda-field%lambdaj)) then
                !
                ! try to select the root#2 for the i-state first 
                !
                if (field%lambda/=0.and.(nint(field%sigmaj-field%sigmai))==( lambda_i(2)-field%lambdaj ) ) then
                  !
                  il_temp = lambda_i(2)
                  lambda_i(2) = lambda_i(1)
                  lambda_i(1) = il_temp
                  !
                  field%lambda = nint(lambda_i(1))
                  !
                  f_t = a
                  a(:,1) = f_t(:,2)
                  a(:,2) = f_t(:,1)
                  !
                elseif( field%lambdaj/=0.and.(nint(field%sigmaj-field%sigmai))==( field%lambda-lambda_j(2) ) ) then
                  !
                  il_temp = lambda_j(2)
                  lambda_j(2) = lambda_j(1)
                  lambda_j(1) = il_temp
                  !
                  jroot = 2
                  field%lambdaj = nint(lambda_j(1))
                  !
                  f_t = b
                  b(:,1) = f_t(:,2)
                  b(:,2) = f_t(:,1)
                  !
                elseif( field%lambdaj/=0.and.(nint(field%sigmaj-field%sigmai))==( lambda_i(2)-lambda_j(2) ) ) then
                  !
                  il_temp = lambda_i(2)
                  lambda_i(2) = lambda_i(1)
                  lambda_i(1) = il_temp
                  !
                  field%lambda = nint(lambda_i(1))
                  !
                  il_temp = lambda_j(2)
                  lambda_j(2) = lambda_j(1)
                  lambda_j(1) = il_temp
                  !
                  jroot = 2
                  field%lambdaj = nint(lambda_j(1))
                  !
                  f_t = a
                  a(:,1) = f_t(:,2)
                  a(:,2) = f_t(:,1)
                  !
                  f_t = b
                  b(:,1) = f_t(:,2)
                  b(:,2) = f_t(:,1)
                  !
                else
                  !
                  write(out,"(/'molpro_duo: cannot find the selecion rule to work for ',2i8)") field%iref,field%jref
                  write(out,"(' sigma = ',2f8.1,' lambda (i) = ',i4,' lamda (j) = ',i4)") field%sigmai,field%sigmaj,lambda_i,lambda_j
                  !
                endif
                !
              endif
              ! 
            case ('L+')
              !
              !write(out,"('molpro_duo: this L+-part is not implemented')")
              !stop 'molpro_duo: this L+-part is not implemented'
              ! 
            case ('DIPOLE')
              !
              !write(out,"('molpro_duo: this Dipole-part is not implemented')")
              !stop 'molpro_duo: this Dipole-part is not implemented'
              !
            case default
              !
              write(out,"(/'molpro_duo: this XX-part is not implemented')")
              stop 'molpro_duo: this XX-part is not implemented'
              !
            end select
            !
            !omp parallel do private(i) schedule(guided)
            do i=1,ngrid
              !
              coupling = 0 
              if (ix_lz_y==0.and.jx_lz_y==0) then
                !
                coupling(1,1) = field%gridvalue(i)*field%complex_f 
                !
              elseif(ix_lz_y/=0.and.jx_lz_y==0) then
                !
                !if ( lambda_i(1)/=1_rk.or.lambda_i(2)/=-1.0_rk) then
                !  !
                !  write(out,"('molpro_duo: lambda_i ',2f8.1,' are not -1 and 1, coupling')") lambda_i,field%iref,field%jref
                !  !stop 'molpro_duo: not for this object'
                !  !
                !endif
                !
                select case(trim(field%class))
                  !
                case('SPINORBIT')
                  !
                  if (abs(nint(field%sigmaj-field%sigmai))/=abs(field%lambda-field%lambdaj)) then
                    !
                    write(out,"('molpro_duo: SO ',2i4,'; illegal selection rules, sigma = ',2f8.1,' lambda = ',2i4)") &
                         field%iref,field%jref,field%sigmai,field%sigmaj,field%lambda,field%lambdaj
                    stop 'molpro_duo: illegal selection rules '
                    !
                  endif
                  !
                  if ( field%sigmai<0 ) then
                    !
                    write(out,"('molpro_duo: SO ',2i4,'; illegal reference sigmai <0 ?',2f8.1)") &
                        field%iref,field%jref,field%sigmai,field%sigmaj
                    !stop 'molpro_duo: illegal reference sigmai'
                    !
                  endif
                  !
                  ! for SOX it is always <1.3| which is given, i.e. we need to solve for the 1st, <1.2| component:
                  !
                  if (field%lambda>0) then 
                    !
                    coupling(2,1) = field%gridvalue(i)*field%complex_f
                    coupling(1,1) =-field%gridvalue(i)*field%complex_f*conjg(a(2,2))/conjg(a(1,2))
                    !
                  else 
                    !
                    coupling(2,1) = field%gridvalue(i)*field%complex_f
                    coupling(1,1) =-field%gridvalue(i)*field%complex_f*conjg(a(2,1))/conjg(a(1,1))
                    !
                  endif 
                  ! 
                case ('L+')
                  !
                  ! eigen-vector 2 is for Lambda
                  !
                  coupling(1,1) = field%gridvalue(i)*field%complex_f*cmplx(0.0_rk,-1.0_rk)  
                  coupling(2,1) = field%gridvalue(i)*field%complex_f*cmplx(0.0_rk, 1.0_rk)*conjg(a(1,2))/conjg(a(2,2))
                  ! 
                case ('DIPOLE')
                  !
                  ! eigen-vector 1 is for -Lambda
                  !
                  coupling(1,1) = field%gridvalue(i)*field%complex_f*(-sqrt(0.5_rk))
                  coupling(2,2) =-field%gridvalue(i)*field%complex_f*(conjg(a(1,2)/a(2,2))*sqrt(0.5_rk))
                  !
                case default
                  !
                  write(out,"('molpro_duo (lambdaj=0): for class ',a,' is not implemented ')") field%class
                  stop 'molpro_duo: not for this object'
                  !
                end select
                !
              elseif(ix_lz_y==0.and.jx_lz_y/=0) then
                !
                !if (lambda_j(1)/=1_rk.or.lambda_j(2)/=-1.0_rk) then
                !  !
                !  !write(out,"('molpro_duo: lambda_j ',2f8.1,' are not -1 and 1, coupling for states',2i)") lambda_j,field%iref,field%jref
                !  !stop 'molpro_duo: not for this object'
                !  !
                !endif
                !
                select case(trim(field%class)) 
                  !
                case('SPINORBIT')
                  !
                  if (abs(nint(field%sigmaj-field%sigmai))/=abs(field%lambda-field%lambdaj)) then
                    !
                    write(out,"('molpro_duo: SO ',2i4,'; illegal selection rules, sigma = ',2f8.1,' lambda = ',2i4)") & 
                          field%iref,field%jref,field%sigmai,field%sigmaj,field%lambda,field%lambdaj
                    stop 'molpro_duo: illegal selection rules '
                    !
                  endif
                  !
                  !if ( field%sigmaj<0 ) then
                  !  !
                  !  write(out,"('molpro_duo: SO ',2i4,'; illegal reference sigmaj <0 ',2f8.1)") & 
                  !        field%iref,field%jref,field%sigmai,field%sigmaj
                  !  stop 'molpro_duo: illegal reference sigmaj'
                  !  !
                  !endif
                  !
                  ! eigen-vector 1 is for Lambda
                  !
                  ! for SOX the non-zero is for |y> vector, i.e. the second component of coupling
                  !
                  !coupling(1,1) = -field%gridvalue(i)*field%complex_f*b(1,2)/b(2,2)
                  !coupling(1,2) = field%gridvalue(i)*field%complex_f

                  ! for SOX it is always <1.3| which is given, i.e. we need to solve for the 1st, <1.2| component:
                  !
                  if (field%lambdaj>0) then 
                    !
                    coupling(1,2) = field%gridvalue(i)*field%complex_f
                    coupling(1,1) =-field%gridvalue(i)*field%complex_f*b(2,1)/b(1,1)
                    !
                  else 
                    !
                    coupling(1,2) = field%gridvalue(i)*field%complex_f
                    coupling(1,1) =-field%gridvalue(i)*field%complex_f*b(2,2)/b(1,2)
                    !
                  endif 
                  ! 
                case('L+')
                  !
                  ! eigen-vector 1 is for Lambda
                  !
                  coupling(1,1) = field%gridvalue(i)*field%complex_f*cmplx(0.0_rk, 1.0_rk)  
                  coupling(1,2) = field%gridvalue(i)*field%complex_f*cmplx(0.0_rk,-1.0_rk)*b(1,2)/b(2,2)
                  ! 
                case ('DIPOLE')
                  !
                  ! eigen-vector 1 is for Lambda
                  !
                  coupling(1,1) = field%gridvalue(i)*field%complex_f*(-sqrt(0.5_rk))
                  coupling(1,2) = field%gridvalue(i)*field%complex_f*(b(1,2)/b(2,2)*sqrt(0.5_rk))
                  !
                case default
                  !
                  write(out,"('molpro_duo (lambdai=0): for class ',a,' is not implemented ')") field%class
                  stop 'molpro_duo: not for this object'
                  !
                end select
                !
              elseif (abs(ix_lz_y)/=abs(jx_lz_y)) then
                !
                select case(trim(field%class))
                  !
                case('SPINORBIT')
                  !
                  if (abs(nint(field%sigmaj-field%sigmai))/=abs(field%lambda-field%lambdaj)) then
                    !
                    write(out,"('molpro_duo: SO ',2i4,'; illegal selection rules, sigma = ',2f8.1,' lambda = ',2i4)") &
                          field%iref,field%jref,field%sigmai,field%sigmaj,field%lambda,field%lambdaj
                    stop 'molpro_duo: illegal selection rules '
                    !
                  endif
                  !
                  if ( field%sigmai<0 ) then
                    !
                    !write(out,"('molpro_duo: SO ',2i4,'; illegal reference sigmai <0 ?',2f8.1)") &
                    !      field%iref,field%jref,field%sigmai,field%sigmaj
                    !stop 'molpro_duo: illegal reference sigmai'
                    !
                  endif
                  !
                  c = field%gridvalue(i)*field%complex_f
                  !
                  coupling(1,1) =  0
                  coupling(1,2) =  c
                  coupling(2,1) =  -c*conjg(a(1,1))*b(2,2)/(conjg(a(2,1))*b(1,2))
                  coupling(2,2) =  0
                  !
                case('DIPOLE')
                  !
                  if (abs(field%lambda-field%lambdaj)/=1) then
                    !
                    write(out,"('molpro_duo: DIPOLE ',2i4,'; illegal selection rules for lambda = ',2i4,' not +/-1')") & 
                          field%iref,field%jref,field%lambda,field%lambdaj
                    stop 'molpro_duo: illegal selection rules for transition dipole'
                    !
                  endif
                  !
                  c = -field%gridvalue(i)*field%complex_f*sqrt(0.5_rk)
                  !
                  ! maple:
                  !c = -conjugate(A[1,2])*a/conjugate(A[2,2]), b = -a*B[1,2]/B[2,2], 
                  !d = B[1,2]*conjugate(A[1,2])*a/(B[2,2]*conjugate(A[2,2]))
                  !
                  coupling(1,1) =  c
                  coupling(1,2) = -c*b(1,2)/b(2,2)
                  coupling(2,1) = -c*conjg(a(1,2))/conjg(a(2,2))
                  coupling(2,2) =  c*b(1,2)*conjg(a(1,2))/(conjg(a(2,2))*b(2,2))
                  !
                case('L+')
                  !
                  if (abs(field%lambda-field%lambdaj)/=1) then
                    !
                    write(out,"('molpro_duo: L+ ',2i4,'; illegal selection rules for lambda = ',2i4,' not +/-1')") & 
                          field%iref,field%jref,field%lambda,field%lambdaj
                    stop 'molpro_duo: L+ illegal selection rules for transition dipole'
                    !
                  endif
                  !
                  ! The <x|Lx+iLy|y> element is <x|Lx|y>
                  !
                  c = field%gridvalue(i)*field%complex_f
                  !
                  ! maple:
                  !
                  !d = -b*conjugate(A[1,2])/conjugate(A[2,2]), c = B[2,2]*b*conjugate(A[1,2])/(B[1,2]*conjugate(A[2,2])), 
                  !a = -B[2,2]*b/B[1,2]
                  !
                  coupling(1,2) =  c
                  coupling(1,1) = -c*b(2,2)/b(1,2)
                  coupling(2,1) =  c*b(2,2)*conjg(a(1,2))/(conjg(a(2,2))*b(1,2))
                  coupling(2,2) = -c*conjg(a(1,2))/conjg(a(2,2))
                  !
                case default
                  !
                  write(out,"('molpro_duo (lambdaj<>lambdai): for class ',a,' is not implemented ')") field%class
                  stop 'molpro_duo: not for this object'
                  !
                end select
                !
              else
                !
                select case(trim(field%class))
                  !
                case('SPINORBIT')
                  !
                  if (nint(field%sigmaj-field%sigmai)/=0) then
                    !
                    write(out,"('molpro_duo: SOZ ',2i4,'; illegal selection rules, sigma = ',2f8.1,' lambda = ',2i4)") & 
                          field%iref,field%jref,field%sigmai,field%sigmaj,field%lambda,field%lambdaj
                    stop 'molpro_duo: SOZ illegal selection rules '
                    !
                  endif
                  !
                  if ( field%sigmai<0 ) then
                    !
                    !write(out,"('molpro_duo: SO ',2i4,'; illegal reference sigmai <0 ',2f8.1)") &
                    !      field%iref,field%jref,field%sigmai,field%sigmaj
                    !stop 'molpro_duo: illegal reference sigmai'
                    !
                  endif
                  !
                  c = field%gridvalue(i)*field%complex_f
                  !
                  !coupling(1,1) =  c
                  !coupling(1,2) =  0
                  !coupling(2,1) =  0
                  !coupling(2,2) = -c*b(1,2)/b(2,2)*conjg(a(1,1))/conjg(a(2,1))
                  !
                  coupling(1,1) =  0
                  coupling(1,2) =  c
                  coupling(2,1) = -conjg(a(1,1))*c*b(2,2)/(conjg(a(2,1))*b(1,2))
                  coupling(2,2) =  0
                  !
                case('DIPOLE')
                  !
                  if (abs(field%lambda-field%lambdaj)/=0) then
                    !
                    write(out,"('molpro_duo: DMZ ',2i4,'; illegal selection rules for lambda = ',2i4,' not 0')") &
                          field%iref,field%jref,field%lambda,field%lambdaj
                    stop 'molpro_duo: illegal selection rules for DMZ'
                    !
                  endif
                  !
                  c = field%gridvalue(i)*field%complex_f
                  !
                  coupling(1,1) =  0
                  coupling(1,2) =  c
                  coupling(2,1) = -conjg(a(1,1))*c*b(2,2)/(conjg(a(2,1))*b(1,2))
                  coupling(2,2) =  0
                  !
                case default
                  !
                  write(out,"('molpro_duo: for class ',a,' is not implemented ')") field%class
                  stop 'molpro_duo: not for this object'
                  !
                end select
                !
              endif
              !
              f_t = matmul( conjg(transpose(a)),matmul(coupling,(b)) )
              !
              field%gridvalue(i) = real(f_t(1,1))
              !
              if (any( abs( aimag( f_t ) )>small_ ) ) then
                !
                write(out,"('molpro_duo: ',a,' ',2i3,'; duo-complex values ',8f8.1)") trim(field%class),field%iref,field%jref,f_t(:,:)
                stop 'molpro_duo: duo-complex values ?'
                !
              endif
              !
              if (abs( real( f_t(1,1) ) )<=sqrt(small_) .and.abs(field%gridvalue(i))>small_) then
                !
                write(out,"('molpro_duo: ',a,' ',2i3,'; duo-zero values ',8f8.1)") trim(field%class),field%iref,field%jref,f_t(:,:)
                stop 'molpro_duo: duo-zero values ?'
                !
              endif
              !
            enddo
            !omp end parallel do

     end subroutine molpro_duo
     !
     subroutine check_and_print_coupling(N,iverbose,fl,name)
       !
       type(fieldT),intent(in) :: fl(:)
       integer(ik),intent(in)  :: N,iverbose
       character(len=*),intent(in) :: name
       integer(ik)             :: i,istate
         !
         if (N<=0.or.iverbose<5) return
         !
         write(out,'(/a)') trim(name)
         !
         ! double check
         !
         do i=1,N
           !
           istate = fl(i)%istate
           jstate = fl(i)%jstate
           !
           if (abs(fl(i)%sigmai)>fl(i)%spini.or.abs(fl(i)%sigmaj)>fl(i)%spinj) then
              write(out,'("For N =",i4," one of sigmas (",2f8.1,") large than  spins (",2f8.1,")")') & 
                        i,fl(i)%sigmai,fl(i)%sigmaj,fl(i)%spini,fl(i)%spinj
              stop 'illegal sigma or spin'
           endif
           if (nint(2.0_rk*fl(i)%spini)+1/=poten(istate)%multi.or. &
               nint(2.0_rk*fl(i)%spinj)+1/=poten(jstate)%multi ) then
              write(out,'("For N =",i3," multi (",2i3,") dont agree with either of multi (",2i3,") of states ",i2," and ",i2)') &
                        i,nint(2.0*fl(i)%spini)+1,nint(2.0*fl(i)%spinj)+1,poten(istate)%multi, &
                        poten(jstate)%multi,istate,jstate
              stop 'illegal multi in map_fields_onto_grid'
           endif
           !
           if (  fl(i)%lambda<-9999.or.fl(i)%lambdaj<-9999 ) then
              write(out,'("For N =",i3," lambdas  are undefined of states ",i2," and ",i2," ",a)') &
                        i,istate,jstate,trim(name)
              stop 'lambdas are undefined: map_fields_onto_grid'
           endif
           !
           if (  abs(fl(i)%lambda)/=poten(istate)%lambda.or.abs(fl(i)%lambdaj)/=poten(jstate)%lambda ) then
              write(out,'("For N =",i3," lambdas (",2i3,") dont agree with either of lambdas (",2i3,") ' // &
                                                                     'of states ",i2," and ",i2)') &
                        i,fl(i)%lambda,fl(i)%lambdaj,poten(istate)%lambda, &
                        poten(jstate)%lambda,istate,jstate
              stop 'illegal lambdas in map_fields_onto_grid'
           endif
           !
           if (  trim(name)=="Spin-Orbit:".and.abs(fl(i)%sigmai)>fl(i)%spini.or.abs(fl(i)%sigmaj)>fl(i)%spinj ) then
              write(out,'("For N =",i3," sigmas (",2f9.2,") dont agree with their spins (",2f9.2,") of states ",i2," and ",i2)') &
                        i,fl(i)%sigmai,fl(i)%sigmai,fl(i)%spini, &
                        fl(i)%spinj,istate,jstate
              stop 'illegal sigmas in map_fields_onto_grid'
           endif
           !
           if ( trim(name)=="Spin-Orbit:".and.fl(i)%sigmai<-9999.0.or.fl(i)%sigmaj<-9999.0 ) then
              write(out,'("For N =",i3," sigmas are undefined for states ",i2," and ",i2," ",a)') &
                        i,istate,jstate,trim(name)
              stop 'sigmas are undefined: map_fields_onto_grid'
           endif
           !
           if ( trim(name)=="Spin-Orbit:".and.fl(i)%sigmai<-9999.0.or.fl(i)%sigmaj<-9999.0 ) then
              write(out,'("For N =",i3," sigmas are undefined for states ",i2," and ",i2," ",a)') &
                        i,istate,jstate,trim(name)
              stop 'sigmas are undefined: map_fields_onto_grid'
           endif
           !
           if ( trim(name)=="<L+> functions:".and.istate==jstate ) then
              write(out,'("For N =",i3," Lx/L+ are defined for the same state ",i2," and ",i2," ",a)') &
                        i,istate,jstate,trim(name)
              stop 'illegal  - diagonal  - L+/Lx coupling: map_fields_onto_grid'
           endif
           !
           if ( trim(name(1:6))=="Lambda".and.istate/=jstate ) then
              write(out,'("For N =",i3," Lambda-doubling must be defined for the same state, not ",i2," and ",i2," ",a)') &
                        i,istate,jstate,trim(name)
              stop 'illegal  - non-diagonal  - Lambda doubling coupling: map_fields_onto_grid'
           endif
           !
         enddo
         !
         do istate=1,N
           write(out,'(i4,2x,a)') istate,trim(fl(istate)%name)
         enddo
         write(my_fmt,'(A,I0,A)') '("        r(Ang)  ",2x,', N, '(i9,10x))'
         write(out,my_fmt) (istate,istate=1,N)
         write(my_fmt,'(A,I0,A)') '(f18.8,', N, '(1x,f18.8))'
         do i=1,ngrid
            write(out,my_fmt) r(i),(fl(istate)%gridvalue(i),istate=1,N)
         enddo
         !
     end subroutine check_and_print_coupling
     !

     !
     subroutine check_and_print_field(N,iverbose,fl,name)
       !
       type(fieldT),intent(in) :: fl(:)
       integer(ik),intent(in)  :: N,iverbose
       character(len=*),intent(in) :: name
       integer(ik)             :: i,istate
           !
           if (N<=0.or.iverbose<5) return
           !
           write(out,'(/a)') trim(name)
           !
           do istate=1,N
              !
              write(out,'(i4,2x,a)') istate,trim(fl(istate)%name)
              !
              ! double check
              if (fl(istate)%lambda == 0 .and.fl(istate)%parity%pm==0 ) then
                 write(out,'("Please define the +/- symmetry of the Lambda=0 state (",i4,")")') istate
                 write(out,'("It is important for the SO component")')
                 stop 'Parity (+/-) for Lambda=0 undefined'
              endif
              !
           enddo
           write(my_fmt, '(A,I0,A)') '("            r(Ang)",', N, '(2x,i20))'
           write(out,my_fmt) (istate,istate=1,N)
           write(my_fmt, '(A,I0,A)') '(f18.8,', N, '(2x,es20.8))'
           do i=1,ngrid
              write(out,my_fmt) r(i),(fl(istate)%gridvalue(i),istate=1,N)
           enddo
           !
     end subroutine check_and_print_field
     !
end subroutine map_fields_onto_grid



  subroutine duo_j0(iverbose_,J_list_,enerout,quantaout,nenerout)
    !
    use accuracy
    use timer
    use input
    use lapack,only : lapack_syev,lapack_heev,lapack_syevr     
     !
     implicit none
     !
     integer(ik),intent(in),optional  :: iverbose_
     !
     real(rk),intent(in),optional  :: J_list_(:) ! range of J values
     !
     real(rk),intent(out),optional  :: enerout(:,:,:)
     type(quantaT),intent(out),optional  :: quantaout(:,:,:)
     integer(ik),intent(out),optional  :: nenerout(:,:)
     !
     real(rk)                :: scale,sigma,omega,omegai,omegaj,spini,spinj,sigmaj,sigmai,jval
     integer(ik)             :: alloc,Ntotal,nmax,iterm,Nlambdasigmas,iverbose
     integer(ik)             :: ngrid,j,i,igrid, jgrid
     integer(ik)             :: ilevel,mlevel,istate,imulti,jmulti,ilambda,jlambda,iso,jstate,jlevel,iobject
     integer(ik)             :: mterm,Nroots,tau_lambdai,irot,ilxly,itau,isigmav
     integer(ik)             :: ilambda_,jlambda_,ilambda_we,jlambda_we,iL2,iss,isso,ibobrot,idiab,totalroots,ivib,jvib,v
     integer(ik)             :: ipermute,istate_,jstate_,nener_total
     real(rk)                :: sigmai_,sigmaj_,f_l2,zpe,spini_,spinj_,omegai_,omegaj_,f_ss,f_bobrot,f_diabatic
     real(rk)                :: sc, h12,f_rot,b_rot,epot,erot
     real(rk)                :: f_t,f_grid,energy_,f_s,f_l,psipsi_t,f_sr
     real(rk)                :: three_j_ref, three_j_,q_we, sigmai_we, sigmaj_we, SO,f_s1,f_s2,f_lo,f_o2,f_o1
     integer(ik)             :: isigma2
     character(len=1)        :: rng,jobz,plusminus(2)=(/'+','-'/)
     character(cl)           :: printout_
     real(rk)                :: vrange(2),veci(2,2),vecj(2,2),pmat(2,2),smat(2,2)
     integer(ik)             :: irange(2),Nsym(2),jsym,isym,Nlevels,jtau,Nsym_,nJ,k
     integer(ik)             :: total_roots,IOunit_quanta,IOunit_vector,irrep,jrrep,isr,ild
     real(rk),allocatable    :: eigenval(:),hmat(:,:),vec(:),vibmat(:,:),vibener(:),hsym(:,:)
     real(rk),allocatable    :: contrfunc(:,:),contrenergy(:),tau(:),J_list(:),Utransform(:,:,:)
     integer(ik),allocatable :: ivib_level2icontr(:,:),iswap(:),Nirr(:,:),ilevel2i(:,:),ilevel2isym(:,:)
     type(quantaT),allocatable :: icontrvib(:),icontr(:)
     character(len=250),allocatable :: printout(:)
     double precision,parameter :: alpha = 1.0d0,beta=0.0d0
     type(matrixT)              :: transform(2)
     type(fieldT),pointer       :: field
     character(len=cl)          :: unitfname
     logical                    :: passed
     !
!      real(rk)                :: my_scale ! scaling factor for the Colbert-Miller method
     !
     !real(rk),allocatable    :: eigenval_(:),hmat_(:,:)
     !
     ! define verbose level
     !
     iverbose = verbose
     if (present(iverbose_)) iverbose = iverbose_
     !
     ! define the range of the angular momentum
     !
     if (present(J_list_)) then
        !
        nJ = size(J_list_)
        !
        allocate(J_list(nJ),stat=alloc)
        !
        J_list = J_list_
        !
     else
        !
        nJ = size(job%J_list)
        allocate(J_list(nJ),stat=alloc)
        J_list = job%J_list
        !
     endif
     !
     if (iverbose>=4) call TimerStart('Map on grid')
     !
     ! Here we map all fields onto the same grid
     call map_fields_onto_grid(iverbose)
     !
     if (iverbose>=4) call TimerStop('Map on grid')
     !
     ! mapping grid
     !
     scale = amass/aston
     !
     h12 = 12.0_rk*hstep**2
     sc  = h12*scale
     !
     b_rot = aston/amass
     !
     ngrid = grid%npoints
     !
     ! First solve and contract the J=0,Sigma=0,Spin=0 problem and then use
     ! the corresponding eigenfunctions as basis set for the main hamiltonian.
     ! For this we use the vibrational hamiltonian + the L2(R) part.
     !
     if (iverbose>=3) write(out,'(/"Construct the J=0 matrix")')
     if (iverbose>=3) write(out,"(a)") 'Solving one-dimentional Schrodinger equations using : ' // trim(solution_method) 
     !
     allocate(vibmat(ngrid,ngrid),vibener(ngrid),contrenergy(ngrid*Nestates),vec(ngrid),contrfunc(ngrid,ngrid*Nestates),stat=alloc)
     call ArrayStart('vibmat',alloc,size(vibmat),kind(vibmat))
     call ArrayStart('vibener',alloc,size(vibener),kind(vibmat))
     call ArrayStart('contrenergy',alloc,size(contrenergy),kind(contrenergy))
     call ArrayStart('vec',alloc,size(vec),kind(vec))
     !
     allocate(icontrvib(ngrid*Nestates),stat=alloc)
     call ArrayStart('contrfunc',alloc,size(contrfunc),kind(contrfunc))
     !
     if (iverbose>=4) call TimerStart('Solve vibrational part')
     !
     ! this will count all vibrational energies obtained for different istates
     totalroots = 0
     !
     zpe = 0
     !
     do istate = 1,Nestates
       !
       vibmat = 0
       !
       if (iverbose>=6) write(out,'("istate = ",i0)') istate
       !
       ! reconstruct quanta for the bra-state
       !
       imulti = poten(istate)%multi
       ilambda = poten(istate)%lambda
       spini = poten(istate)%spini
       !
       if (iverbose>=4) call TimerStart('Build vibrational Hamiltonian')
       !
       !$omp parallel do private(igrid,f_rot,epot,f_l2,iL2,erot) shared(vibmat) schedule(guided)
       do igrid =1, ngrid
         !
         if (iverbose>=6) write(out,'("igrid = ",i0)') igrid
         !
         ! the centrifugal factor will be needed for the L**2 term
         !
         f_rot=b_rot/r(igrid)**2*sc
         !
         !
         ! the diagonal term with the potential function
         !
         epot = poten(istate)%gridvalue(igrid)*sc
         !
         !
         ! Another diagonal term:
         ! The L^2 term (diagonal): (1) L2(R) is used if provided otherwise
         ! an approximate value Lambda*(Lamda+1) is assumed.
         !
         f_l2 = 0 ! real(ilambda*(ilambda+1),rk)*f_rot
         do iL2 = 1,Nl2
           if (L2(iL2)%istate==istate.and.L2(iL2)%jstate==istate) then
             f_l2 = f_rot*L2(iL2)%gridvalue(igrid)
             exit
           endif
         enddo
         !
         erot = f_l2
         !
         ! the diagonal matrix element will include PEC +L**2 as well as the vibrational kinetic contributions.
         vibmat(igrid,igrid) = epot + erot

         method_choice: select case(solution_method)
           case ("5POINTDIFFERENCES") ! default 
             vibmat(igrid,igrid) = vibmat(igrid,igrid) + d2dr(igrid)
             !
             ! The nondiagonal matrix elemenets are:
             ! The vibrational kinetic energy operator will connect only the
             ! neighbouring grid points igrid+/1 and igrid+/2.
             !
             ! Comment by Lorenzo Lodi
             ! The following method corresponds to approximating the second derivative of the wave function
             ! psi''  by the 5-point finite difference formula:
             !
             ! f''(0) = [-f(-2h) +16*f(-h) - 30*f(0) +16*f(h) - f(2h) ] / (12 h^2)  + O( h^4 )
             !
            if (igrid>1) then
              vibmat(igrid,igrid-1) = -16.0_rk*z(igrid-1)*z(igrid)
              vibmat(igrid-1,igrid) = vibmat(igrid,igrid-1)
            endif
             !
            if (igrid>2) then
              vibmat(igrid,igrid-2) = z(igrid-2)*z(igrid)
              vibmat(igrid-2,igrid) = vibmat(igrid,igrid-2)
            endif

            case("SINC")   ! Experimental part using Colbert Miller sinc DVR (works only for uniform grids at the moment)
              vibmat(igrid,igrid) = vibmat(igrid,igrid) +(12._rk)* PI**2 / 3._rk

               do jgrid =igrid+1, ngrid
                 vibmat(igrid,jgrid) = +(12._rk)*2._rk* real( (-1)**(igrid+jgrid), rk) / real(igrid - jgrid, rk)**2
                 vibmat(jgrid,igrid) = vibmat(igrid,jgrid)
               enddo

            case default
             write(out, '(A)') 'Error: unrecognized solution method' // trim(solution_method)
             write(out, '(A)') 'Possible options are: '
             write(out, '(A)') '                      5POINTDIFFERENCES'
             write(out, '(A)') '                      SINC'
            end select method_choice

       enddo
       !$omp end parallel do
       !
       if (iverbose>=4) call TimerStop('Build vibrational Hamiltonian')
       !
       ! diagonalize the vibrational hamiltonian using the DSYEVR routine from LAPACK
       !
       jobz = 'V'
       vrange(1) = -0.0_rk ; vrange(2) = (job%vibenermax)*sc
       irange(1) = 1 ; irange(2) = min(job%vibmax(istate),Ngrid)
       nroots = Ngrid
       rng = 'A'
       if (job%vibenermax<1e8) then
          rng = 'V'
       elseif (job%vibmax(istate)/=1e8) then
          rng = 'I'
       endif
       !
       call lapack_syevr(vibmat,vibener,rng=rng,jobz=jobz,iroots=nroots,vrange=vrange,irange=irange)
       !
       if (nroots<1) then
         nroots = 1
         vibener = 0
         vibmat = 0
         vibmat(1,1) = 1.0_rk
       endif
       !
       ! ZPE is obatined only from the lowest state
       !
       if (istate==1) zpe = vibener(1)
       !
       ! write the pure vibrational energies and the corresponding eigenfunctions into global matrices
       contrfunc(:,totalroots+1:totalroots+nroots) = vibmat(:,1:nroots)
       contrenergy(totalroots+1:totalroots+nroots) = vibener(1:nroots)
       !
       ! assign the eigenstates with quanta
       do i=1,nroots
         icontrvib(totalroots + i)%istate =  istate
         icontrvib(totalroots + i)%v = i-1
       enddo
       !
       ! increment the global counter of the vibrational states
       !
       totalroots = totalroots + nroots
       !
     enddo
     !
     ! sorting basis states (energies, basis functions and quantum numbers) from different
     ! states all together according with their energies
     !
     do ilevel = 1,totalroots
       !
       energy_ = contrenergy(ilevel)
       !
       do jlevel=ilevel+1,totalroots
         !
         if ( energy_>contrenergy(jlevel) ) then
           !
           ! energy
           !
           energy_=contrenergy(jlevel)
           contrenergy(jlevel) = contrenergy(ilevel)
           contrenergy(ilevel) = energy_
           !
           ! basis function
           !
           vec(:) = contrfunc(:,jlevel)
           contrfunc(:,jlevel) = contrfunc(:,ilevel)
           contrfunc(:,ilevel) = vec(:)
           !
           ! qunatum numbers
           !
           istate = icontrvib(jlevel)%istate
           icontrvib(jlevel)%istate = icontrvib(ilevel)%istate
           icontrvib(ilevel)%istate = istate
           !
           i = icontrvib(jlevel)%v
           icontrvib(jlevel)%v = icontrvib(ilevel)%v
           icontrvib(ilevel)%v = i
           !
         endif
         !
       enddo
       !
     enddo
     !
     ! print out the vibrational fields in the J=0 representaion
     if (iverbose>=4) then
        write(out,'(/"Vibrational (contracted) energies: ")')
        write(out,'("    N        Energy/cm    State v"/)')
        do i = 1,totalroots
          istate = icontrvib(i)%istate
          write(out,'(i5,f18.6," [ ",2i4," ] ",a)') i,(contrenergy(i)-contrenergy(1))/sc,istate,icontrvib(i)%v, &
                                                    trim(poten(istate)%name)
        enddo
     endif
     !
     ! check the orthogonality of the basis
     !
     if (iverbose>=6) then
       !
       write(out,'(/"Check the contracted basis for ortho-normality")')
       !
       !$omp parallel do private(ilevel,jlevel,psipsi_t) schedule(guided)
       do ilevel = 1,totalroots
         do jlevel = 1,ilevel
           !
           if (icontrvib(ilevel)%istate/=icontrvib(jlevel)%istate) cycle
           !
           psipsi_t  = sum(contrfunc(:,ilevel)*contrfunc(:,jlevel))
           !
           if (ilevel/=jlevel.and.abs(psipsi_t)>sqrt(small_)) then
              write(out,"('orthogonality is brocken : <',i4,'|',i4,'> (',f16.6,')')") ilevel,jlevel,psipsi_t
              stop 'Brocken orthogonality'
           endif
           !
           if (ilevel==jlevel.and.abs(psipsi_t-1.0_rk)>sqrt(small_)) then
              write(out,"('normalization is brocken:  <',i4,'|',i4,'> (',f16.6,')')") ilevel,jlevel,psipsi_t
              stop 'Brocken normalization'
           endif
           !
           ! Reporting the quality of the matrix elemenst
           !
           if (iverbose>=6) then
             if (ilevel/=jlevel) then
               write(out,"('<',i4,'|',i4,'> = ',e16.2,'<-',8x,'0.0')") ilevel,jlevel,psipsi_t
             else
               write(out,"('<',i4,'|',i4,'> = ',f16.2,'<-',8x,'1.0')") ilevel,jlevel,psipsi_t
             endif
           endif
           !
         enddo
       enddo
       !$omp end parallel do
       !
     endif
     !
     ! dealocate some objects
     !
     deallocate(vibmat,vibener)
     call ArrayStop('vibmat')
     call ArrayStop('vibener')
     deallocate(vec)
     call ArrayStop('vec')
     !
     if (iverbose>=4) call TimerStop('Solve vibrational part')
     !
     ! Now we need to compute all vibrational matrix elements of all field of the Hamiltonian, except for the potentials V,
     ! which together with the vibrational kinetic energy operator are diagonal on the contracted basis developed
     !
     ! allocate arrays for matrix elements for all hamiltonian fields
     !
     ! introducing a new field for the centrifugal matrix
     !
     allocate(brot(1),stat=alloc)
     allocate(brot(1)%matelem(totalroots,totalroots),stat=alloc)
     call ArrayStart('brot',alloc,size(brot(1)%matelem),kind(brot(1)%matelem))
     !
     do iobject = 1,Nobjects
        !
        if (iobject==Nobjects-2) cycle
        !
        if (iobject==Nobjects.and.iverbose>=4.and.action%intensity) then 
           !
           write(out,'(/"Vibrational transition moments: ")')
           write(out,'("    State    TM   State"/)')
           !
        endif
        !
        Nmax = fieldmap(iobject)%Nfields
        !
        ! each field type constits of Nmax terms
        !
        do iterm = 1,Nmax
          !
          select case (iobject)
            !
          case (1)
            field => poten(iterm)
          case (2)
            field => spinorbit(iterm)
          case (3)
            field => l2(iterm)
          case (4)
            field => lxly(iterm)
            field%gridvalue(:) = field%gridvalue(:)*b_rot/r(:)**2*sc
          case (5)
            field => spinspin(iterm)
          case (6)
            field => spinspino(iterm)
          case (7)
            field => bobrot(iterm)
            field%gridvalue(:) = field%gridvalue(:)*b_rot/r(:)**2*sc
          case (8)
            field => spinrot(iterm)
          case (9)
            field => diabatic(iterm)
          case (10)
            field => lambdaopq(iterm)
          case (11)
            field => lambdap2q(iterm)
          case (12)
            field => lambdaq(iterm)
          case (Nobjects-2)
            field => abinitio(iterm)
          case (Nobjects-1)
            field => brot(iterm)
            field%name = 'BROT'
            allocate(field%gridvalue(ngrid),stat=alloc)
            call ArrayStart(field%name,alloc,size(field%gridvalue),kind(field%gridvalue))
            field%gridvalue(:) = b_rot/r(:)**2*sc
          case (Nobjects)
            if (.not.action%intensity) cycle 
            field => dipoletm(iterm)
          end select
          !
          allocate(field%matelem(totalroots,totalroots),stat=alloc)
          call ArrayStart(field%name,alloc,size(field%matelem),kind(field%matelem))
          !
          !$omp parallel do private(ilevel,jlevel) schedule(guided)
          do ilevel = 1,totalroots
            do jlevel = 1,ilevel
              !
              ! in the grid representation of the vibrational basis set
              ! the matrix elements are evaluated simply by a sumation of over the grid points
              !
              field%matelem(ilevel,jlevel)  = sum(contrfunc(:,ilevel)*(field%gridvalue(:))*contrfunc(:,jlevel))
              field%matelem(jlevel,ilevel) = field%matelem(ilevel,jlevel)
              !
            enddo
          enddo
          !$omp end parallel do
          !
          ! printing out transition moments 
          !
          if (iobject==Nobjects.and.action%intensity) then
              !
              !write(out,'(/"Vibrational transition moments: ")')
              !write(out,'("    State    TM   State"/)')
              !
              do ilevel = 1,totalroots
                do jlevel = 1,totalroots
                  !
                  istate = icontrvib(ilevel)%istate
                  jstate = icontrvib(jlevel)%istate
                  !
                  ! dipole selection rules
                  !
                  if (nint(field%spini-field%spinj)==0.and.abs(field%lambda-field%lambdaj)<=1) then 
                     !
                     !field%matelem(ilevel,jlevel) = field%matelem(ilevel,jlevel)*field%factor
                     !
                     if ( iverbose>=4.and.abs(field%matelem(ilevel,jlevel))>sqrt(small_).and.istate==field%istate.and.&
                          jstate==field%jstate ) then 
                       !                           hard limit to field name, may lead to truncation
                       write(out,'("<",i2,",",i4,"|",a40,5x,"|",i2,",",i4,"> = ",f18.8)') icontrvib(ilevel)%istate,       & 
                                                                                          icontrvib(ilevel)%v,            &
                                                                                          trim(field%name),                     &
                                                                                          icontrvib(jlevel)%istate,       &
                                                                                          icontrvib(jlevel)%v,            &
                                                                                          field%matelem(ilevel,jlevel)
                       !
                     endif
                    !
                  else
                    !
                    field%matelem(ilevel,jlevel) = 0
                    !
                  endif 
                  !
                  ! in the grid representation of the vibrational basis set
                  ! the matrix elements are evaluated simply by a sumation of over the grid points
                  !
                enddo
              enddo
          endif 
          !
        enddo
        !
     enddo
     !
     ! checkpoint the matrix elements of dipoles if required 
     !
     !if (trim(job%IO_dipole=='SAVE')) then 
     !!    call check_point_dipoles('SAVE',iverbose,totalroots) 
     !endif
     !
     ! First we start a loop over J - the total angular momentum quantum number
     !
     if (action%intensity) then
       !
       allocate(eigen(nJ,sym%Nrepresen),basis(nJ),stat=alloc)
       if (alloc/=0) stop 'problem allocating eigen'
       !
       ! initialize the following fields
       do irot = 1,nJ
         do irrep = 1,sym%Nrepresen
           eigen(irot,irrep)%Nlevels = 0
         enddo
       enddo
       !
     endif
     !
     if (present(nenerout)) nenerout = 0
     !
     if (present(enerout)) then
       enerout = 0
     endif
     !
     loop_jval : do irot = 1,nJ
       !
       jval = J_list(irot)
       !
       if (jval<jmin) cycle
       !
       if (iverbose>=4) write(out,'(/"j = ",f9.1/)') jval
       !
       ! define the bookkeeping of the quantum numbers for the sigma-lambda basis set
       !
       if (iverbose>=3) write(out,'("Define the quanta book-keeping")')
       !
       call define_quanta_bookkeeping(iverbose,jval,Nestates,Nlambdasigmas)
       !
       if (iverbose>=3) write(out,'("...done!")')
       !
       ! Now we combine together the vibrational and sigma-lambda basis functions (as product)
       ! and the corresponding quantum numbers to form our final contracted basis set as well as
       ! the numbering of the contratced basis functions using only one index i.
       !
       ! first count the contracted states of the product basis set
       !
       i = 0
       do ilevel = 1,Nlambdasigmas
         do ivib =1, totalroots
           if (quanta(ilevel)%istate/=icontrvib(ivib)%istate) cycle
           i = i + 1
         enddo
       enddo
       !
       ! this how many states we get in total after the product of the
       ! vibrational and sigma-lambda basis sets:
       Ntotal = i
       !
       if (Ntotal==0) then
         write(out,'("The size of the rovibronic basis set is zero. Check the CONTRACTION parameters.")')
         stop "The size of the rovibronic basis set is zero"
       endif
       !
       ! allocate the book keeping array to manage the mapping between
       ! the running index i and the vibrational ivib and lamda-sigma ilevel quantum numbers
       allocate(ivib_level2icontr(Nlambdasigmas,ivib),icontr(Ntotal),printout(Nlambdasigmas),stat=alloc)
       call ArrayStart('ivib_level2icontr',alloc,size(ivib_level2icontr),kind(ivib_level2icontr))
       printout = ''
       !
       if (iverbose>=4) write(out,'(/"Contracted basis set:")')
       if (iverbose>=4) write(out,'("     i     jrot ilevel ivib state v     spin    sigma lambda   omega   Name")')
       !
       ! biuld the bookkeeping: the object icontr will store this informtion
       !
       i = 0
       do ilevel = 1,Nlambdasigmas
         !
         istate = quanta(ilevel)%istate
         sigma = quanta(ilevel)%sigma
         imulti = quanta(ilevel)%imulti
         ilambda = quanta(ilevel)%ilambda
         omega = quanta(ilevel)%omega
         spini = quanta(ilevel)%spin
         tau_lambdai = 0 ; if (ilambda<0) tau_lambdai = 1
         !
         do ivib =1,totalroots
           if (quanta(ilevel)%istate/=icontrvib(ivib)%istate) cycle
           i = i + 1
           !
           ivib_level2icontr(ilevel,ivib) = i
           icontr(i) = quanta(ilevel)
           icontr(i)%ivib = ivib
           icontr(i)%ilevel = ilevel
           icontr(i)%v = icontrvib(ivib)%v
           !
           ! print the quantum numbers
           if (iverbose>=4) then
               write(out,'(i6,1x,f8.1,1x,i4,1x,i4,1x,i4,1x,i4,1x,f8.1,1x,f8.1,1x,i4,1x,f8.1,3x,a)') &
                       i,jval,ilevel,ivib,istate,&
                       icontr(i)%v,spini,sigma,ilambda,omega,poten(istate)%name
           endif
           !
         enddo
       enddo
       !
       ! allocate the hamiltonian matrix and an array for the energies of this size Ntotal
       allocate(hmat(Ntotal,Ntotal),stat=alloc)
       call ArrayStart('hmat',alloc,size(hmat),kind(hmat))
       !
       if (iverbose>=4) call MemoryReport
       !
       hmat = 0
       !
       if (trim(job%IO_eigen)=='SAVE') then
         !
         unitfname ='Quantum numbers of the eigensolution'
         call IOStart(trim(unitfname),IOunit_quanta)
         !
         !Prepare the i/o-file for the the eigenvectors
         ! 
         unitfname ='Eigenvectors in the contracted represent'
         call IOStart(trim(unitfname),IOunit_vector)
         !
       endif
       !
       if (iverbose>=4) call TimerStart('Construct the hamiltonian')
       !
       if (iverbose>=3) write(out,'(/"Construct the hamiltonian matrix")')
       !
       !omp parallel do private(i,ivib,ilevel,istate,sigmai,imulti,ilambda,omegai,spini,jvib,jlevel,jstate,sigmaj,  & 
       !                        jmulti,jlambda,omegaj,spinj,f_rot,erot,iL2,field,f_l2,f_s,f_t,iso,ibraket,ipermute, &
       !                        istate_,ilambda_,sigmai_,spini_,jstate_,jlambda_,sigmaj_,spinj_,isigmav,omegai_,    &
       !                        omegaj_,itau,ilxly,f_grid,f_l,f_ss) shared(hmat) schedule(guided)
       do i = 1,Ntotal
         !
         ivib = icontr(i)%ivib
         ilevel = icontr(i)%ilevel
         !
         istate = icontr(i)%istate
         sigmai = icontr(i)%sigma
         imulti = icontr(i)%imulti
         ilambda = icontr(i)%ilambda
         omegai = icontr(i)%omega
         spini = icontr(i)%spin
         !
         ! the diagonal contribution is the energy from the contracted vibrational solution
         !
         hmat(i,i) = contrenergy(ivib)
         !
         do j =i,Ntotal
            !
            jvib = icontr(j)%ivib
            jlevel = icontr(j)%ilevel
            jstate = icontr(j)%istate
            sigmaj = icontr(j)%sigma
            jmulti = icontr(j)%imulti
            jlambda = icontr(j)%ilambda
            omegaj = icontr(j)%omega
            spinj = icontr(j)%spin
            !
            if (iverbose>=6) write(out,'("ilevel,ivib = ",2(i0,2x) )') ilevel,ivib
            !
            ! the centrifugal factor will be needed for different terms
            !
            f_rot=brot(1)%matelem(ivib,jvib)
            !
            ! BOB centrifugal (rotational) term, i.e. a correction to f_rot
            !
            do ibobrot = 1,Nbobrot
              if (bobrot(ibobrot)%istate==istate.and.bobrot(ibobrot)%jstate==jstate.and.istate==jstate) then
                field => bobrot(ibobrot)
                f_bobrot = field%matelem(ivib,jvib)
                f_rot = f_rot + f_bobrot
                exit
              endif
            enddo
            !
            ! diagonal elements
            !
            if (ilevel==jlevel) then
              !                                             ! L Lodi -job%diag_L2_fact is either zero or one
              erot = f_rot*( Jval*(Jval+1.0_rk) - omegai**2 -job%diag_L2_fact*real(ilambda**2,rk)  & 
                       +   spini*(spini+1.0_rk) - sigmai**2 )
              !
              ! add the diagonal matrix element to the local spin-rotational matrix hmat
              hmat(i,j) = hmat(i,j) + erot
              !
              ! Diagonal spin-spin term
              !
              do iss = 1,Nss
                if (spinspin(iss)%istate==istate.and.spinspin(iss)%jstate==jstate.and.istate==jstate) then
                  field => spinspin(iss)
                  f_ss = field%matelem(ivib,jvib)*(3.0_rk*sigmai**2-spini*(spini+1.0_rk))*sc
                  hmat(i,j) = hmat(i,j) + f_ss
                  exit
                endif
              enddo
              !
              ! Diagonal spin-rotation term
              !
              do isr = 1,Nsr
                if (spinrot(isr)%istate==istate.and.spinrot(isr)%jstate==jstate.and.istate==jstate) then
                  field => spinrot(isr)
                  f_sr = field%matelem(ivib,jvib)*(sigmai**2-spini*(spini+1.0_rk))*sc
                  hmat(i,j) = hmat(i,j) + f_sr
                  exit
                endif
              enddo
              !
              ! print out the internal matrix at the first grid point
              if (iverbose>=4.and.abs(hmat(i,j)) >small_) then
                  write(printout(ilevel),'(A, F15.3,A)') "RV=", hmat(i,j)/sc, "; "
              endif
              !
            endif
            !
            ! Non diagonal L2 term
            !
            do iL2 = 1,Nl2
              if (L2(iL2)%istate==istate.and.L2(iL2)%jstate==jstate.and.istate/=jstate) then
                field => L2(iL2)
                f_l2 = f_rot*field%matelem(ivib,jvib)
                hmat(i,j) = hmat(i,j) + f_l2
                exit
              endif
            enddo
            !
            ! Diabatic non-diagonal contribution  term
            !
            do idiab = 1,Ndiabatic
              if (diabatic(idiab)%istate==istate.and.diabatic(idiab)%jstate==jstate.and.&
                  abs(nint(sigmaj-sigmai))==0.and.(ilambda==jlambda).and.nint(spini-spinj)==0 ) then
                field => diabatic(idiab)
                f_diabatic = field%matelem(ivib,jvib)
                hmat(i,j) = hmat(i,j) + f_diabatic
                exit
              endif
            enddo
            !
            ! Non-diagonal spin-spin term
            !
            do isso = 1,Nsso
              !
              if (spinspino(isso)%istate==istate.and.spinspino(isso)%jstate==jstate.and.istate==jstate.and.&
                  abs(nint(sigmaj-sigmai))==1.and.(ilambda-jlambda)==nint(sigmaj-sigmai)) then
                 !
                 field => spinspino(isso)
                 !
                 f_s = sigmaj-sigmai
                 !
                 !f_t = sqrt( (spinj-f_s*sigmaj )*( spinj + f_s*sigmaj+1.0_rk ) )*&
                 !      sqrt( (jval -f_s*omegaj )*( jval  + f_s*omegaj+1.0_rk ) )
                 !
                 f_t = sqrt( spini*(spini+1.0_rk)-(sigmai+0.5_rk*f_s)*(sigmai    ) )*&
                       sqrt( spini*(spini+1.0_rk)-(sigmai+0.5_rk*f_s)*(sigmai+f_s) )
                 !
                 f_ss = field%matelem(ivib,jvib)*f_t*sc
                 !
                 hmat(i,j) = hmat(i,j) + f_ss
                 !
                 ! print out the internal matrix at the first grid point
                 if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                    write(printout_,'("    SS-o",2i3)') ilevel,jlevel
                    printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    if (abs(hmat(i,j))>sqrt(small_)) then
                      write(printout_,'(g12.4)') hmat(i,j)/sc
                      printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                 endif
                 !
              endif
              ! 
            enddo
            !
            ! Non-diagonal spin-rotaion term
            !
            do isr = 1,Nsr
              !
              field => spinrot(isr)
              !
              ! Two options are possible: 
              ! 1. <Sigma,Omega,Lambda|HSR|Sigma+/-1,Omega+/-1,Lambda>
              ! 2. <Sigma,Omega,Lambda|HSR|Sigma+/-1,Omega,Lambda-/+>
              !
              ! 1. <Sigma,Omega,Lambda|HSR|Sigma+/-1,Omega+/-1,Lambda>
              if (spinrot(isr)%istate==istate.and.spinrot(isr)%jstate==jstate.and.istate==jstate.and.&
                  abs(nint(sigmaj-sigmai))==1.and.(ilambda==jlambda).and.nint(spini-spinj)==0) then
                 !
                 f_s = sigmaj-sigmai
                 !
                 f_t = sqrt( jval* (jval +1.0_rk)-omegai*(omegai+f_s) )*&
                       sqrt( spini*(spini+1.0_rk)-sigmai*(sigmai+f_s) )
                 !
                 f_sr = field%matelem(ivib,jvib)*f_t*sc
                 !
                 hmat(i,j) = hmat(i,j) + f_sr*0.5_rk
                 !
                 ! print out the internal matrix at the first grid point
                 if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                    write(printout_,'("    SR",2i3)') ilevel,jlevel
                    printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    if (abs(hmat(i,j))>sqrt(small_)) then
                      write(printout_,'(g12.4)') hmat(i,j)/sc
                      printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                 endif
                 !
              endif
              !
              ! 2. <Sigma,Omega,Lambda|HSR|Sigma+/-1,Omega,Lambda-/+>
              ! with the effective parameter gamma_v including the matrix element <Lambda|L+/-|lambda-/+1>
              if (spinrot(isr)%istate==istate.and.spinrot(isr)%jstate==jstate.and.&
                  abs(nint(sigmaj-sigmai))==1.and.abs(ilambda-jlambda)==1.and.nint(spini-spinj)==0) then
                  !
                  do ipermute  = 0,1
                    !
                    if (ipermute==0) then
                      !
                      istate_ = field%istate ; ilambda_ = field%lambda  
                      jstate_ = field%jstate ; jlambda_ = field%lambdaj 
                      !
                    else  ! permute
                      !
                      jstate_ = field%istate ; jlambda_ = field%lambda 
                      istate_ = field%jstate ; ilambda_ = field%lambdaj
                      !
                    endif
                    !
                    ! however the permutation makes sense only when for non diagonal <State,Lambda,Spin|F|State',Lambda',Spin'>
                    ! otherwise it will cause a double counting:
                    !
                    if (ipermute==1.and.istate_==jstate_.and.ilambda_==jlambda_) cycle
                    !
                    ! check if we at the right electronic states
                    if( istate/=istate_.or.jstate/=jstate_ ) cycle
                    !
                    ! We should also take into account that Lambda can change sign (only Lambda>0 is given in input)
                    ! In order to recover other combinations we apply the symmetry transformation
                    ! laboratory fixed inversion which is equivalent to the sigmav operation 
                    !                    (sigmav= 0 correspond to the unitary transformation)
                    do isigmav = 0,1
                      !
                      ! the permutation is only needed if at least some of the quanta is not zero. otherwise it should be skipped to
                      ! avoid the double counting.
                      if( isigmav==1.and. abs( field%lambda ) + abs( field%lambdaj )==0 ) cycle
               
                      ! do the sigmav transformations (it simply changes the sign of lambda and sigma simultaneously)
                      ilambda_ = ilambda_*(-1)**isigmav
                      jlambda_ = jlambda_*(-1)**isigmav
                      !
                      ! proceed only if the quantum numbers of the field equal to the corresponding <i| and |j> quantum numbers:
                      if (ilambda_/=ilambda.or.jlambda_/=jlambda) cycle
                      !
                      !
                      ! double check
                      if (spini/=poten(istate)%spini.or.spinj/=poten(jstate)%spini) then
                       write(out,'("SR: reconstructed spini ",f8.1," or spinj ",f8.1," do not agree with stored values ", & 
                                  & f8.1,1x,f8.1)') spini,spinj,poten(istate)%spini,poten(jstate)%spini
                        stop 'SR: wrongly reconsrtucted spini or spinj'
                      endif
                      !
                      f_grid  = field%matelem(ivib,jvib)
                      !
                      ! <Lx> and <Ly> don't depend on Sigma
                      !
                      ! L*S part of the spin-rotation 
                      !
                      ! the selection rules are Delta Sigma = - Delta Lambda (Delta Spin = 0)
                      !
                      ! factor to switch between <Sigma+1|S+|Sigma> and <Sigma-1|S-|Sigma>:
                      f_s = real(ilambda-jlambda,rk)
                      !
                      ! the bra-component of Sigma (i.e. sigmaj):
                      sigmaj_ = sigmai+f_s
                      !
                      ! make sure that this sigmaj_ is consistent with the current ket-sigmaj
                      if (nint(2.0_rk*sigmaj_)==nint(2.0*sigmaj)) then
                        !
                        f_t = f_grid
                        !
                        ! the result of the symmetry transformation:
                        if (isigmav==1) then
                          !
                          ! we assume that
                          ! sigmav <Lamba|L+|Lambda'> => <-Lamba|L-|-Lambda'> == <Lamba|L+|Lambda'>(-1)^(Lamba+Lambda')
                          ! and <Lamba|L+|Lambda'> is an unique quantity given in the input
                          ! however we don't apply the sigmav transformation to sigma or omega
                          ! since we only need to know how <Lamba|L+/-|Lambda'> transforms in order to relate it to the
                          ! value given in input.
                          !
                          itau = 0 
                          !
                          if (ilambda_==0.and.poten(istate)%parity%pm==-1) itau = itau+1
                          if (jlambda_==0.and.poten(jstate)%parity%pm==-1) itau = itau+1
                          !
                          f_t = f_t*(-1.0_rk)**(itau)
                          !
                        endif
                         !
                        ! the matrix element <Sigmai| S+/- |Sigmai+/-1>
                        !
                        f_t = sqrt( (spini-f_s*sigmai)*(spini+f_s*sigmai+1.0_rk) )*f_t
                        !
                        !f_t = sqrt( spini*(spini+1.0_rk)-sigmai*(sigmai+f_s)  )*f_t
                        !
                        hmat(i,j) = hmat(i,j) - f_t*0.5_rk
                        !
                        ! print out the internal matrix at the first grid point
                        if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                           write(printout_,'(i3,"-SR",2i3)') ilxly,ilevel,jlevel
                           printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                           write(printout_,'(g12.4)') hmat(i,j)/sc
                           printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                        endif
                        !
                      endif
                      !
                    enddo
                    !
                  enddo
                  !
              endif
              ! 
            enddo
            !
            ! J*S part
            !
            ! The selection rules are Delta Spin=0, Delta Lambda = 0, Delta Sigma = +/- 1
            ! and (CHECK!!) istate==jstate (?)
            !
            if (abs(nint(sigmaj-sigmai))==1.and.ilambda==jlambda.and.nint(spini-spinj)==0.and.istate==jstate) then
              !
              !if (nint(sigmai-sigmaj)/=nint(omegai-omegaj)) cycle
              !
              f_s = sigmaj-sigmai
              !
              !f_t = sqrt( (spinj-f_s*sigmaj )*( spinj + f_s*sigmaj+1.0_rk ) )*&
              !      sqrt( (jval -f_s*omegaj )*( jval  + f_s*omegaj+1.0_rk ) )
              !
              f_t = sqrt( spini*(spini+1.0_rk)-sigmai*(sigmai+f_s) )*&  !== sqrt( ... sigmai*sigmaj)
                    sqrt( jval* (jval +1.0_rk)-omegai*(omegai+f_s) )    !== sqrt( ... omegai*omegaj)
              !
              hmat(i,j) = hmat(i,j) - f_t*f_rot
              !
              !hmat(j,i) = hmat(i,j)
              !
              if ((nint(omegai-omegaj))/=nint(sigmai-sigmaj)) then
                write(out,'("S*J: omegai-omegaj/=sigmai-sigmaj ",2f8.1,2x,2f8.1," for i,j=",2(i0,2x))') omegai,omegaj, &
                                                                                                       sigmai,sigmaj,i,j
                stop 'S*J: omegai/=omegaj+/-1 '
              endif
              !
              ! print out the internal matrix at the first grid point
              if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                 write(printout_,'("  JS(",2i3,")=")') ilevel,jlevel
                 printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                 if (abs(hmat(i,j))>sqrt(small_)) then
                   write(printout_,'(F12.4, A)') hmat(i,j)/sc, " ;"
                   printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                 endif
              endif
              !
            endif
            !
            ! spin-orbit part:
            loop_iso : do iso =1,Nspinorbits
              !
              field => spinorbit(iso)
              !
              ! The selection rules are (Lefebvre-Brion and Field, Eq. (3.4.6)): 
              ! Delta J = 0 ; Delta Omega  = 0 ; g<-/->u; e<->f; Sigma+<->Sigma-;
              ! Delta S = 0 or Delta S = 1 ; Delta Lambda = Delta Sigma = 0 or Delta Lambda = - Delta Sigma = +/- 1
              !
              if (nint(omegai-omegaj)/=0.or.nint(spini-spinj)>1 ) cycle
              if ( ilambda==0.and.jlambda==0.and.poten(istate)%parity%pm==poten(jstate)%parity%pm ) cycle
              if ( poten(istate)%parity%gu/=0.and.poten(istate)%parity%gu/=poten(jstate)%parity%gu ) cycle
              !
              do ipermute  = 0,1
                !
                if (ipermute==0) then
                  !
                  istate_ = field%istate ; ilambda_we = field%lambda  ; sigmai_we = field%sigmai ; spini_ = field%spini
                  jstate_ = field%jstate ; jlambda_we = field%lambdaj ; sigmaj_we = field%sigmaj ; spinj_ = field%spinj
                  !
                else  ! permute
                  !
                  jstate_ = field%istate ; jlambda_we = field%lambda  ; sigmaj_we = field%sigmai ; spinj_ = field%spini
                  istate_ = field%jstate ; ilambda_we = field%lambdaj ; sigmai_we = field%sigmaj ; spini_ = field%spinj
                  !
                endif
                ! proceed only if the spins of the field equal the corresponding <i| and |j> spins of the current matrix elements. 
                ! otherwise skip it:
                if ( nint(spini_-spini)/=0.or.nint(spinj_-spinj)/=0 ) cycle
                !
                ! however the permutation makes sense only when for non diagonal <State,Lambda,Spin|F|State',Lambda',Spin'>
                ! otherwise it will cause a double counting:
                !
                if (ipermute==1.and.istate_==jstate_.and.ilambda_we==jlambda_we.and.nint(sigmai_we-sigmaj_we)==0.and. & 
                    nint(spini_-spinj_)==0) cycle
                !
                ! check if we at the right electronic states
                if( istate/=istate_.or.jstate/=jstate_ ) cycle
                !
                ! We apply the Wigner-Eckart theorem to reconstruct all combinations of <Lamba Sigma |HSO|Lamba Sigma' > 
                ! connected with the reference (input) <Lamba Sigma_r |HSO|Lamba Sigma_r' > by this theorem. 
                ! Basically, we loop over Sigma (Sigma = -S..S).  The following 3j-symbol for the reference states will 
                ! be conidered:
                ! / Si      k  Sj     \    k  = 1
                ! \ -Sigmai q  Sigmaj /    q  = Sigmai - Sigmaj
                !
                ! reference q from Wigner-Eckart
                q_we = sigmai_we-sigmaj_we
                !
                ! We should consider also a permutation <State',Lambda',Spin'|F|State,Lambda,Spin> if this makes a change.
                ! This could be imortant providing that we constrain the i,j indexes to be i<=j (or i>=j).
                ! We also assume that the matrix elements are real!
                !
                ! First of all we can check if the input values are not unphysical and consistent with Wigner-Eckart:
                ! the corresponding three_j should be non-zero:
                three_j_ref = three_j(spini_, 1.0_rk, spinj_, -sigmai_we, q_we, sigmaj_we)
                !
                if (abs(three_j_ref)<small_) then 
                  !
                  write(out,"('The Spin-orbit field ',2i3,' is incorrect according to Wigner-Eckart, three_j = 0 ')") & 
                        field%istate,field%jstate
                  write(out,"('Check S_i, S_j, Sigma_i, Sigma_j =  ',4f9.2)") spini_,spinj_,sigmai_we,sigmaj_we
                  stop "The S_i, S_j, Sigma_i, Sigma_j are inconsistent"
                  !
                end if 
                !
                ! Also check the that the SO is consistent with the selection rules for SO
                !
                if ( ilambda_we-jlambda_we+nint(sigmai_we-sigmaj_we)/=0.or.nint(spini_-spinj_)>1.or.&
                   ( ilambda_we==0.and.jlambda_we==0.and.poten(field%istate)%parity%pm==poten(field%jstate)%parity%pm ).or.&
                   ( (ilambda_we-jlambda_we)/=-nint(sigmai_we-sigmaj_we) ).or.&
                      abs(ilambda_we-jlambda_we)>1.or.abs(nint(sigmai_we-sigmaj_we))>1.or.&
                   ( poten(field%istate)%parity%gu/=0.and.poten(field%istate)%parity%gu/=poten(field%jstate)%parity%gu ) ) then
                   !
                   write(out,"('The quantum numbers of the spin-orbit field ',2i3,' are inconsistent" // &
                                   " with SO selection rules: ')") field%istate,field%jstate
                   write(out,"('Delta J = 0 ; Delta Omega  = 0 ; g<-/->u; e<-/->f; Sigma+<->Sigma-; " // &
                      "Delta S = 0 or Delta S = 1 ; Delta Lambda = Delta Sigma = 0 or Delta Lambda = - Delta Sigma = +/- 1')")
                   write(out,"('Check S_i, S_j, Sigma_i, Sigma_j, lambdai, lambdaj =  ',4f9.2,2i4)") &
                                                                      spini_,spinj_,sigmai_we,sigmaj_we,ilambda_we,jlambda_we
                   stop "The S_i, S_j, Sigma_i, Sigma_j lambdai, lambdaj are inconsistent with selection rules"
                   !
                endif
                !
                do isigma2 = -nint(2.0*spini_),nint(2.0*spini_),2
                  !
                  ! Sigmas from Wigner-Eckart
                  sigmai_ = real(isigma2,rk)*0.5 
                  sigmaj_ = sigmai_ - q_we
                  !
                  ! three_j for current Sigmas
                  three_j_ = three_j(spini_, 1.0_rk, spinj_, -sigmai_, q_we, sigmaj_)
                  !
                  ! current value of the SO-matrix element from Wigner-Eckart
                  SO = (-1.0_rk)**(sigmai_-sigmai_we)*three_j_/three_j_ref*field%matelem(ivib,jvib)
                  !
                  ! We should also take into account that Lambda and Sigma can change sign
                  ! since in the input we give only a unique combination of matrix elements, for example
                  ! < 0 0 |  1  1 > is given, but < 0 0 | -1 -1 > is not, assuming that the program will generate the missing
                  ! combinations.
                  !
                  ! In order to recover other combinations we apply the symmetry transformation
                  ! laboratory fixed inversion which is equivalent to the sigmav operation 
                  !                    (sigmav= 0 correspond to the unitary transformation)
                  do isigmav = 0,1
                    !
                    ! sigmav is only needed if at least some of the quanta is not zero. otherwise it should be skipped to
                    ! avoid the double counting.
                    if( isigmav==1.and.nint( abs( 2.0*sigmai_ )+ abs( 2.0*sigmaj_ ) )+abs( ilambda_we )+abs( jlambda_we )==0 ) cycle
                    !
                    ! do the sigmav transformations (it simply changes the sign of lambda and sigma simultaneously)
                    ilambda_ = ilambda_we*(-1)**isigmav
                    jlambda_ = jlambda_we*(-1)**isigmav
                    sigmai_ = sigmai_*(-1.0_rk)**isigmav
                    sigmaj_ = sigmaj_*(-1.0_rk)**isigmav
                    !
                    omegai_ = sigmai_+real(ilambda_)
                    omegaj_ = sigmaj_+real(jlambda_)
                    !
                    ! Check So selection rules
                    if ( ( ilambda_-jlambda_)/=-nint(sigmai_-sigmaj_).or.abs(sigmai_-sigmaj_)>1.or.omegai_/=omegaj_ ) cycle
                    !
                    ! proceed only if the quantum numbers of the field equal
                    ! to the corresponding <i| and |j> quantum numbers of the basis set. otherwise skip it:
                    if ( nint(sigmai_-sigmai)/=0.or.nint(sigmaj_-sigmaj)/=0.or.ilambda_/=ilambda.or.jlambda_/=jlambda ) cycle
                    !
                    f_t = SO*sc
                    !
                    ! the result of the symmetry transformtaion applied to the <Lambda,Sigma|HSO|Lambda',Sigma'> only
                    if (isigmav==1) then
                      !
                      ! still not everything is clear here: CHECK!
                      !
                      itau = -ilambda_-jlambda_ +nint(spini_-sigmai_)+nint(spinj_-sigmaj_) !+nint(jval-omegai)+(jval-omegaj)
                      !
                      !itau = nint(spini_-sigmai_)+nint(spinj_-sigmaj_) ! +nint(jval-omegai)+(jval-omegaj)
                      !
                      !itau = 0
                      !
                      if (ilambda_==0.and.poten(istate)%parity%pm==-1) itau = itau+1
                      if (jlambda_==0.and.poten(jstate)%parity%pm==-1) itau = itau+1
                      !
                      f_t = f_t*(-1.0_rk)**(itau)
                      !
                    endif
                    !
                    ! double check
                    if ( nint(omegai-omegai_)/=0 .or. nint(omegaj-omegaj_)/=0 ) then
                      write(out,'(A,f8.1," or omegaj ",f8.1," do not agree with stored values ",f8.1,1x,f8.1)') &
                                 "SO: reconsrtucted omegai", omegai_,omegaj_,omegai,omegaj
                      stop 'SO: wrongly reconsrtucted omegai or omegaj'
                    endif
                    !
                    ! we might end up in eilther parts of the matrix (upper or lower),
                    ! so it is safer to be general here and
                    ! don't restrict to lower part as we have done above
                    !
                    hmat(i,j) = hmat(i,j) + f_t
                    !
                    !hmat(j,i) = hmat(i,j)
                    !
                    ! print out the internal matrix at the first grid point
                    if (iverbose>=4.and.abs(hmat(i,j))>small_) then
                        !
                        write(printout_,'(i3,"-SO",2i3)') iso,ilevel,jlevel
                        printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                        write(printout_,'(g12.4)') f_t/sc
                        printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                       !
                    endif
                    !
                    cycle loop_iso
                    !
                  enddo
                enddo
              enddo
            enddo  loop_iso
            !
            !
            ! L*S and J*L parts
            !
            loop_ilxly : do ilxly =1,Nlxly
              !
              field => lxly(ilxly)
              !
              ! Also check that L+ is consistent with the selection rules
              !
              if ( field%istate==field%jstate .or.abs(field%lambda-field%lambdaj)/=1 ) then
                 !
                 write(out,"('The quantum numbers of the L+/Lx field ',2i3,' are inconsistent" // &
                                 " with L+selection rules: ')") field%istate,field%jstate
                 write(out,"('Delta Lamda = +/-1')")
                 stop "Lx/L+ input is inconsistent with selection rules"
                 !
              endif
              !
              ! the field entry in the input gives only one combination of the quantum numbers for
              ! the matrix element <State,Lambda,Spin|F|State',Lambda',Spin'>
              ! LxLy  4 6 ;  lambda  0 1 ; spin   1.0 1.0
              ! we should consider also a permutation <State',Lambda',Spin'|F|State,Lambda,Spin> if this makes a change.
              ! This could be imortant providing that we constrain the i,j indexes to be i<=j (or i>=j)
              ! We also assume that the matrix elements are real!
              !
              do ipermute  = 0,1
                !
                if (ipermute==0) then
                  !
                  istate_ = field%istate ; ilambda_ = field%lambda  ; spini_ = field%spini
                  jstate_ = field%jstate ; jlambda_ = field%lambdaj ; spinj_ = field%spinj
                  !
                else  ! permute
                  !
                  jstate_ = field%istate ; jlambda_ = field%lambda  ; spinj_ = field%spini
                  istate_ = field%jstate ; ilambda_ = field%lambdaj ; spini_ = field%spinj
                  !
                endif
                !
                ! however the permutation makes sense only when for non diagonal <State,Lambda,Spin|F|State',Lambda',Spin'>
                ! otherwise it will cause a double counting:
                !
                if (ipermute==1.and.istate_==jstate_.and.ilambda_==jlambda_.and.nint(spini_-spinj_)==0) cycle
                !
                ! check if we at the right electronic states
                if( istate/=istate_.or.jstate/=jstate_ ) cycle
                !
                ! We should also take into account that Lambda can change sign (only Lambda>0 is given in input)
                ! In order to recover other combinations we apply the symmetry transformation
                ! laboratory fixed inversion which is equivalent to the sigmav operation 
                !                    (sigmav= 0 correspond to the unitary transformation)
                do isigmav = 0,1
                  !
                  ! the permutation is only needed if at least some of the quanta is not zero. otherwise it should be skipped to
                  ! avoid the double counting.
                  if( isigmav==1.and. abs( field%lambda ) + abs( field%lambdaj )==0 ) cycle

                  ! do the sigmav transformations (it simply changes the sign of lambda and sigma simultaneously)
                  ilambda_ = ilambda_*(-1)**isigmav
                  jlambda_ = jlambda_*(-1)**isigmav
                  !
                  ! proceed only if the quantum numbers of the field equal to the corresponding <i| and |j> quantum numbers:
                  if (istate/=istate_.or.jstate_/=jstate.or.ilambda_/=ilambda.or.jlambda_/=jlambda) cycle
                  !
                  ! check the selection rule Delta Lambda = +/1
                  if (abs(ilambda-jlambda)/=1) cycle
                  !
                  ! double check
                  if (spini/=poten(istate)%spini.or.spinj/=poten(jstate)%spini) then
                   write(out,'("LJ: reconstructed spini ",f8.1," or spinj ",f8.1," do not agree with stored values ", & 
                              & f8.1,1x,f8.1)') spini,spinj,poten(istate)%spini,poten(jstate)%spini
                    stop 'LJ: wrongly reconsrtucted spini or spinj'
                  endif
                  !
                  f_grid  = field%matelem(ivib,jvib)
                  !
                  ! <Lx> and <Ly> don't depend on Sigma
                  !
                  ! L*S part
                  !
                  ! the selection rules are Delta Sigma = - Delta Lambda (Delta Spin = 0)
                  !
                  ! factor to switch between <Sigma+1|S+|Sigma> and <Sigma-1|S-|Sigma>:
                  f_s = real(ilambda-jlambda,rk)
                  !
                  ! the bra-component of Sigma (i.e. sigmaj):
                  sigmaj_ = sigmai+f_s
                  !
                  ! make sure that this sigmaj_ is consistent with the current ket-sigmaj
                  if (nint(2.0_rk*sigmaj_)==nint(2.0*sigmaj)) then
                    !
                    f_t = f_grid
                    !
                    ! the result of the symmetry transformation:
                    if (isigmav==1) then
                      !
                      ! we assume that
                      ! sigmav <Lamba|L+|Lambda'> => <-Lamba|L-|-Lambda'> == <Lamba|L+|Lambda'>(-1)^(Lamba+Lambda')
                      ! and <Lamba|L+|Lambda'> is an unique quantity given in the input
                      ! however we don't apply the sigmav transformation to sigma or omega
                      ! since we only need to know how <Lamba|L+/-|Lambda'> transforms in order to relate it to the
                      ! value given in input.
                      !
                      !itau = ilambda-jlambda+nint(spini-sigmai)+nint(spinj-sigmaj)!-nint(omegai+omegaj)
                      !
                      ! we try to remove also lambda from the sigmav transformation!!
                      !
                      itau = 0 !!!! ilambda-jlambda
                      !
                      !itau = ilambda-jlambda
                      !
                      if (ilambda_==0.and.poten(istate)%parity%pm==-1) itau = itau+1
                      if (jlambda_==0.and.poten(jstate)%parity%pm==-1) itau = itau+1
                      !
                      f_t = f_t*(-1.0_rk)**(itau)
                      !
                      ! change the sign of <|L+|> to get sigmav*<|L+|>=-<|L-|> if necessary
                      !! f_t = sign(1.0_rk,f_s)*f_t
                      !
                    endif
                     !
                    ! the matrix element <Sigmai| S+/- |Sigmai+/-1>
                    !
                    f_t = sqrt( (spini-f_s*sigmai)*(spini+f_s*sigmai+1.0_rk) )*f_t
                    !
                    !f_t = sqrt( spini*(spini+1.0_rk)-sigmai*(sigmai+f_s)  )*f_t
                    !
                    hmat(i,j) = hmat(i,j) + f_t
                    !hmat(j,i) = hmat(i,j)
                    !
                    ! print out the internal matrix at the first grid point
                    if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                       write(printout_,'(i3,"-LS",2i3)') ilxly,ilevel,jlevel
                       printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                       write(printout_,'(g12.4)') hmat(i,j)/sc
                       printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                    !
                  endif
                  !
                  ! L*J part
                  !
                  ! The selection rule is simple: Delta Sigma = 0, Delta Spin = 0,
                  ! i.e. bra and ket sigma are equal:
                  !
                  if (nint(2.0_rk*sigmai)==nint(2.0*sigmaj)) then
                    !
                    ! however omega should change by 1 (via J+/-) exactly as lambda changes (with L-/+):
                    ! (f_l will be needed to switch between J+ and J-)
                    f_l = real(jlambda-ilambda,rk)
                    !
                    ! we should obtain  omegaj = omega+f_l
                    ! double check
                    if ( nint( 2.0_rk*omegaj )/=nint( 2.0_rk*(omegai+f_l) ) ) then
                       write(out,'("L*J omegaj ",f8.1," does agree with assumed ",f8.1," value omegai+/-1")') omegaj,omegai+f_l
                       stop 'wrongly reconsrtucted omegaj'
                    endif
                    !
                    f_t = f_grid
                    !
                    ! the result of the symmetry transformation sigmav:
                    !
                    if (isigmav==1) then
                      !
                      ! we assume that
                      ! sigmav <Lamba|L+|Lambda'> => <-Lamba|L-|-Lambda'> == <Lamba|L+|Lambda'>(-1)^(Lamba+Lambda')
                      ! and <Lamba|L+|Lambda'> is an unique quantity given in the input
                      ! (see alos above)
                      !
                      !itau = ilambda-jlambda+nint(spini-sigmai)+nint(spinj-sigmaj)-nint(omegai+omegaj)
                      !
                      ! we try now removing lambda from sigmav transormation!!!
                      !
                      itau = 0 !! ilambda-jlambda
                      !
                      !itau = ilambda-jlambda
                      !
                      if (ilambda==0.and.poten(istate)%parity%pm==-1) itau = itau+1
                      if (jlambda==0.and.poten(jstate)%parity%pm==-1) itau = itau+1
                      !
                      f_t = f_t*(-1.0_rk)**(itau)
                      !
                    endif
                    !
                    ! For <Omega|<Lambda|L+ J- |Lambda+1>|Omega+1> f_l = 1
                    ! For <Omega|<Lambda|L- J+ |Lambda-1>|Omega-1> f_l =-1
                    !
                    f_t = sqrt( (jval-f_l*omegai)*(jval+f_l*omegai+1.0_rk) )*f_t
                    !
                    !f_t = sqrt( jval*(jval+1.0_rk)-omegai*(omega+f_l) )*f_t
                    !
                    hmat(i,j) = hmat(i,j) - f_t
                    !hmat(j,i) = hmat(i,j)
                    !
                    ! print out the internal matrix at the first grid point
                    if (iverbose>=4.and.abs(hmat(i,j))>small_) then
                       write(printout_,'(i3,"-LJ",2i3)') ilxly,ilevel,jlevel
                       printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                       write(printout_,'(g12.4)') hmat(i,j)/sc
                       printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                    !
                  endif
                  !
                enddo
                !
              enddo
              !
            enddo loop_ilxly
            !
            !
            ! Non-diagonal lambda-o doubling
            !
            do ild = 1,Nlambdaopq
              !
              field => lambdaopq(ild)
              !
              ! 1. <Sigma,Omega,Lambda|Lambda-O|Sigma+/-2,Omega,-Lambda>
              if (lambdaopq(ild)%istate==istate.and.lambdaopq(ild)%jstate==jstate.and.istate==jstate.and.&
                  abs(ilambda)==1.and.(ilambda-jlambda)==nint(sigmaj-sigmai).and.abs(nint(sigmaj-sigmai))==2.and.(ilambda==-jlambda).and.nint(spini-spinj)==0.and.nint(omegai-omegaj)==0) then
                 !
                 f_s2 = sigmai-sigmaj
                 f_s1 = sign(1.0_rk,f_s2)
                 !
                 f_t = sqrt( spini*(spini+1.0_rk)-(sigmaj     )*(sigmaj+f_s1) )*&
                       sqrt( spini*(spini+1.0_rk)-(sigmaj+f_s1)*(sigmaj+f_s2) )
                 !
                 f_lo = field%matelem(ivib,jvib)*f_t*sc
                 !
                 hmat(i,j) = hmat(i,j) + f_lo*0.5_rk
                 !
                 ! print out the internal matrix at the first grid point
                 if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                    write(printout_,'("    LO",2i3)') ilevel,jlevel
                    printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    if (abs(hmat(i,j))>sqrt(small_)) then
                      write(printout_,'(g12.4)') hmat(i,j)/sc
                      printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                 endif
                 !
              endif
              ! 
            enddo
            !
            ! Non-diagonal lambda-p doubling
            !
            do ild = 1,Nlambdap2q
              !
              field => lambdap2q(ild)
              !
              ! 1. <Sigma,Omega,Lambda|Lambda-p|Sigma+/-1,Omega-/+1,Lambda>
              if (lambdap2q(ild)%istate==istate.and.lambdap2q(ild)%jstate==jstate.and.istate==jstate.and.&
                 abs(ilambda)==1.and.abs(nint(sigmaj-sigmai))==1.and.(ilambda==-jlambda).and.nint(spini-spinj)==0.and.&
                 abs(nint(omegai-omegaj))==1.and.nint(sigmaj-sigmai)==nint(omegai-omegaj).and.&
                 nint(sigmaj-sigmai+omegai-omegaj)==(ilambda-jlambda)) then
                 !
                 f_s = sigmai-sigmaj
                 !
                 f_t = sqrt( spini*(spini+1.0_rk)-sigmaj*(sigmaj+f_s) )*&
                       sqrt( jval* (jval +1.0_rk)-omegaj*(omegaj-f_s) )  
                 !
                 f_lo = field%matelem(ivib,jvib)*f_t*sc
                 !
                 hmat(i,j) = hmat(i,j) - f_lo*0.5_rk
                 !
                 ! print out the internal matrix at the first grid point
                 if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                    write(printout_,'("    LP",2i3)') ilevel,jlevel
                    printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    if (abs(hmat(i,j))>sqrt(small_)) then
                      write(printout_,'(g12.4)') hmat(i,j)/sc
                      printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                 endif
                 !
              endif
              ! 
            enddo
            !
            ! Non-diagonal lambda-q doubling
            !
            do ild = 1,Nlambdaq
              !
              field => lambdaq(ild)
              !
              ! 1. <Sigma,Omega,Lambda|Lambda-O|Sigma+/-2,Omega,-Lambda>
              if (lambdaq(ild)%istate==istate.and.lambdaq(ild)%jstate==jstate.and.istate==jstate.and.&
                  abs(ilambda)==1.and.(ilambda-jlambda)==nint(omegaj-omegai).and.abs(nint(sigmaj-sigmai))==0.and.&
                     (ilambda==-jlambda).and.nint(spini-spinj)==0.and.nint(omegai-omegaj)==2) then
                 !
                 f_o2 = omegaj-omegai
                 f_o1 = sign(1.0_rk,f_o2)
                 !
                 f_t = sqrt( jval*(jval+1.0_rk)-(omegaj     )*(omegaj-f_o1) )*&
                       sqrt( jval*(jval+1.0_rk)-(omegaj-f_o1)*(omegaj-f_o2) )
                 !
                 f_lo = field%matelem(ivib,jvib)*f_t*sc
                 !
                 hmat(i,j) = hmat(i,j) + f_lo*0.5_rk
                 !
                 ! print out the internal matrix at the first grid point
                 if (iverbose>=4.and.abs(hmat(i,j))>sqrt(small_)) then
                    write(printout_,'("    LO",2i3)') ilevel,jlevel
                    printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    if (abs(hmat(i,j))>sqrt(small_)) then
                      write(printout_,'(g12.4)') hmat(i,j)/sc
                      printout(ilevel) = trim(printout(ilevel))//trim(printout_)
                    endif
                 endif
                 !
              endif
              ! 
            enddo
            !
         enddo  ! j
       enddo  ! i
       !omp end parallel do
       !
       if (iverbose>=3) write(out,'("...done!")')
       !
       if (iverbose>=5) then
          ! print out the structure of the submatrix
          !
          write(out,'(/"Non-zero matrix elements of the coupled Sigma-Lambda matrix:")')
          write(out, '(A, ES10.2,A)') 'Threshold for printing is ', small_, ' cm^-1'
          write(out,'(A)') 'RV == Rotational-vibrational'
          write(out,'(A)') 'SO == Spin-Orbit interaction'
          write(out,'(A)') 'SS == Spin-Spin interaction'
          write(out,'(A)') 'JS == J.S interaction (aka S-uncoupling)'
          write(out,'(A)') 'LS == L.J interaction (aka L-uncoupling)'
          write(out,'(A)') 'LS == L.S interaction (spin-electronic)'
          !
          do ilevel = 1,Nlambdasigmas
            write(out,'(a)') trim( printout(ilevel) )
          enddo
          !
          write(out,'(" "/)')
          !
       endif
       !
       if (iverbose>=4) call TimerStop('Construct the hamiltonian')
       !
       ! Transformation to the symmetrized basis set
       !
       ! |v,Lambda,Sigma,J,Omega,tau> = 1/sqrt(2) [ |v,Lambda,Sigma,J,Omega>+(-1)^tau |v,-Lambda,-Sigma,J,-Omega> ]
       !
       allocate(iswap(Ntotal),vec(Ntotal),Nirr(Ntotal,2),ilevel2i(Ntotal,2),tau(Ntotal),ilevel2isym(Ntotal,2),stat=alloc)
       call ArrayStart('iswap-vec',alloc,size(iswap),kind(iswap))
       call ArrayStart('iswap-vec',alloc,size(vec),kind(vec))
       call ArrayStart('Nirr',alloc,size(Nirr),kind(Nirr))
       !
       iswap = 0
       Nsym = 0
       Nlevels = 0
       ilevel2i = 0
       ilevel2isym = 0
       Nirr = 0
       !
       !omp parallel do private(istate,sigmai,ilambda,spini,omegai,ibib,j,jstate,sigmaj,jlambda,omegaj,spinj,jvib) & 
       !                        shared(iswap,vec) schedule(guided)
       do i = 1,Ntotal
         !
         istate = icontr(i)%istate
         sigmai = icontr(i)%sigma
         ilambda = icontr(i)%ilambda
         spini = icontr(i)%spin
         omegai = real(ilambda,rk)+sigmai
         ivib    = icontr(i)%v
         !
         if (iswap(i)/=0) cycle
         !
         if (ilambda==0.and.nint(sigmai)==0) then
           !
           Nlevels = Nlevels + 1

           itau = nint(spini+Jval)
           if (poten(istate)%parity%pm==-1) itau = itau+1
           !
           itau = abs(itau)
           !
           tau(Nlevels) = (-1.0_rk)**itau
           !
           if (mod(itau,2)==1) then
             Nsym(2) = Nsym(2) + 1
             ilevel2isym(Nlevels,2) = nsym(2)
             ilevel2i(Nlevels,2) = i
             Nirr(Nlevels,2) = 1
           else
             Nsym(1) = Nsym(1) + 1
             ilevel2isym(Nlevels,1) = nsym(1)
             ilevel2i(Nlevels,1) = i
             Nirr(Nlevels,1) = 1
           endif
           !
           iswap(i) = i
           !ilevel2i(Nlevels,1) = i
           !
         else
           !
           do  j = 1,Ntotal
             !
             jstate  = icontr(j)%istate
             sigmaj  = icontr(j)%sigma
             jlambda = icontr(j)%ilambda
             omegaj  = real(jlambda,rk)+sigmaj
             spinj   = icontr(j)%spin
             jvib    = icontr(j)%v
             !
             if (ilambda==-jlambda.and.nint(2.0*sigmai)==-nint(2.0*sigmaj).and. &
                 istate==jstate.and.ivib==jvib.and.nint(2.0*spini)==nint(2.0*spinj)) then
               !
               Nsym(:) = Nsym(:) + 1
               Nlevels = Nlevels + 1
               Nirr(Nlevels,:) = 1
               !
               if (ilambda>jlambda.or.sigmaj<sigmai) then
                 !
                 ilevel2i(Nlevels,1) = i
                 ilevel2i(Nlevels,2) = j
                 !
               else
                 !
                 ilevel2i(Nlevels,1) = j
                 ilevel2i(Nlevels,2) = i
                 !
               endif
               !
               ilevel2isym(Nlevels,1:2) = nsym(1:2)
               !
               itau = -ilambda+nint(spini-sigmai)+nint(Jval-omegai)
               !
               if (ilambda==0.and.poten(istate)%parity%pm==-1) itau = itau+1
               !
               tau(Nlevels) = (-1.0_rk)**itau
               !
               iswap(i) = j*(-1)**itau
               iswap(j) = i*(-1)**itau
               !
               exit
               !
             endif
             !
           enddo
           !
         endif
         !
       enddo
       !omp end parallel do
       !
       ! Nleveles is the number of states disregarding the degeneracy 
       ! Nroots is the total number of roots inlcuding the degenerate states 
       !
       allocate(transform(1)%matrix(max(1,Nsym(1)),max(1,Nsym(1))),stat=alloc)
       allocate(transform(2)%matrix(max(1,Nsym(2)),max(1,Nsym(2))),stat=alloc)
       allocate(transform(1)%irec( max( 1,Nsym(1) ) ),stat=alloc)
       allocate(transform(2)%irec( max( 1,Nsym(2) ) ),stat=alloc)
       !
       call ArrayStart('transform',alloc,size(transform(1)%matrix),kind(transform(1)%matrix))
       call ArrayStart('transform',alloc,size(transform(2)%matrix),kind(transform(2)%matrix))
       call ArrayStart('transform',alloc,size(transform(1)%irec),kind(transform(1)%irec))
       call ArrayStart('transform',alloc,size(transform(2)%irec),kind(transform(2)%irec))
       !
       allocate(Utransform(Nlevels,2,2),stat=alloc)
       call ArrayStart('Utransform',alloc,size(Utransform),kind(Utransform))
       !
       ! Building the transformation to the symmetrized representaion 
       !
       do ilevel = 1,Nlevels
         !
         veci = 0
         !
         if (any(Nirr(ilevel,:)==0)) then
           !
           do irrep = 1,sym%Nrepresen
             do itau = 1,Nirr(ilevel,irrep)
               !
               i = ilevel2i(ilevel,irrep)
               istate = icontr(i)%istate
               veci(irrep,irrep) = 1.0_rk
               isym = ilevel2isym(ilevel,irrep)
               transform(irrep)%irec(isym) = ilevel
               !
             enddo
           enddo
           !
           !
           !if (tau(ilevel)<0) then
           !  veci(1,2) = 1.0_rk
           !  isym = ilevel2isym(ilevel,2)
           !  transform(2)%irec(isym) = ilevel
           !else
           !  veci(1,1) = 1.0_rk
           !  isym = ilevel2isym(ilevel,1)
           !  transform(1)%irec(isym) = ilevel
           !endif
           !
         else
           !
           veci(1,1) = sqrt(0.5_rk)
           veci(2,1) = sqrt(0.5_rk)*tau(ilevel)
           veci(1,2) = sqrt(0.5_rk)
           veci(2,2) =-sqrt(0.5_rk)*tau(ilevel)
           !
           do irrep = 1,sym%Nrepresen
              isym = ilevel2isym(ilevel,irrep)
              transform(irrep)%irec(isym) = ilevel
           enddo
           !
           !do itau=1,Nirr(ilevel)
           !  !
           !  isym = ilevel2isym(ilevel,itau)
           !  transform(itau)%irec(isym) = ilevel ! ilevel2i(ilevel,itau)
           !  !
           !enddo
           !
         endif
         !
         Utransform(ilevel,:,:) = veci(:,:)
         !
         do jlevel = 1,Nlevels
           !
           vecj = 0
           !
           !if (Nirr(jlevel)==1) then
           !  !
           !  j = ilevel2i(jlevel,1)
           !  if (j==0) j = ilevel2i(jlevel,2)
           !  !
           !  jstate = icontr(j)%istate
           !  !
           !  if (tau(jlevel)<0) then
           !    vecj(1,2) = 1.0_rk
           !    jsym = ilevel2isym(jlevel,2)
           !    !transform(2)%irec(jsym) = i
           !  else
           !    vecj(1,1) = 1.0_rk
           !    jsym = ilevel2isym(jlevel,1)
           !    !transform(1)%irec(jsym) = i
           !  endif
           !
           if (any(Nirr(jlevel,:)==0)) then
              !
              do jrrep = 1,sym%Nrepresen
                do jtau = 1,Nirr(jlevel,jrrep)
                  vecj(jrrep,jrrep) = 1.0_rk
                enddo
              enddo
              !
           else
              !
              vecj(1,1) = sqrt(0.5_rk)
              vecj(2,1) = sqrt(0.5_rk)*tau(jlevel)
              vecj(1,2) = sqrt(0.5_rk)
              vecj(2,2) =-sqrt(0.5_rk)*tau(jlevel)
              !
           endif
           !
           pmat = 0
           !
           do isym = 1,2
              do itau = 1,Nirr(ilevel,isym)
                 i = ilevel2i(ilevel,isym)
                 do jsym = 1,2
                    do jtau = 1,Nirr(jlevel,jsym)
                       j = ilevel2i(jlevel,jsym)
                       !
                       if (i<=j) then
                         pmat(isym,jsym) = hmat(i,j)
                       else
                         pmat(isym,jsym) = hmat(j,i)
                       endif
                       !
                    enddo
                 enddo
              enddo
           enddo

           !do isym=1,Nirr(ilevel)
           !  i = ilevel2i(ilevel,isym)
           !  do jsym=1,Nirr(jlevel)
           !     j = ilevel2i(jlevel,jsym)
           !     !
           !     if (i<=j) then
           !       pmat(isym,jsym) = hmat(i,j)
           !     else
           !       pmat(isym,jsym) = hmat(j,i)
           !     endif
           !     !
           !  enddo
           !enddo
           !
           smat = matmul(transpose(veci),matmul(pmat,vecj))
           !
           !smat = matmul((veci),matmul(pmat,transpose(vecj)))
           !
           do irrep = 1,sym%Nrepresen
              do itau = 1,Nirr(ilevel,irrep)
                 !i = ilevel2i(ilevel,isym)
                 !
                 isym = ilevel2isym(ilevel,irrep)
                 !
                 do jrrep = 1,sym%Nrepresen
                    do jtau = 1,Nirr(jlevel,jrrep)
                       !j = ilevel2i(jlevel,jsym)
                       jsym = ilevel2isym(jlevel,jrrep)
                       !
                       if (irrep==jrrep) then
                         !
                         transform(irrep)%matrix(isym,jsym) = smat(irrep,irrep)
                         !
                       else
                         !
                         if (abs(smat(irrep,jrrep))>sqrt(small_)) then
                           !
                           i = ilevel2i(ilevel,itau)
                           j = ilevel2i(jlevel,jtau)
                           !
                           istate = icontr(i)%istate
                           sigmai = icontr(i)%sigma
                           ilambda = icontr(i)%ilambda
                           spini = icontr(i)%spin
                           omegai = real(ilambda,rk)+sigmai
                           ivib    = icontr(i)%v
                           !
                           jstate  = icontr(j)%istate
                           sigmaj  = icontr(j)%sigma
                           jlambda = icontr(j)%ilambda
                           omegaj  = real(jlambda,rk)+sigmaj
                           spinj   = icontr(j)%spin
                           jvib    = icontr(j)%v
                           !
                           write(out,'(/"Problem with symmetry: The non-diagonal matrix element is not zero:")')
                           write(out,'(/"i,j = ",2i8," irrep,jrrep = ",2i8," isym,jsym = ",2i8," ilevel,jlevel = ", &
                                      & 2i3," , matelem =  ",g16.9," with zero = ",g16.9)') &
                                      i,j,irrep,jrrep,isym,jsym,ilevel,jlevel,smat(itau,jtau),sqrt(small_)
                           write(out,'(/"<State   v  lambda spin   sigma  omega |H(sym)| State   v  lambda spin   sigma  omega>")')
                           write(out,'("<",i3,2x,2i4,3f8.1," |H(sym)| ",i3,2x,2i4,3f8.1,"> /= 0")') &
                                       istate,ivib,ilambda,spini,sigmai,omegai,jstate,jvib,jlambda,spinj,sigmaj,omegaj
                           write(out,'("<",a10,"|H(sym)|",a10,"> /= 0")') trim(poten(istate)%name),trim(poten(jstate)%name)
                           !
                           stop 'Problem with symmetry: The non-diagonal matrix element is not zero'
                           !
                         endif
                         !
                       endif
                       !
                    enddo
                 enddo
              enddo
           enddo

         enddo
         !
       enddo
       !
       ! Now we diagonalize the two matrices contrcuted one by one 
       !
       if (iverbose>=2) write(out,'(/"Eigenvalues for J = ",f8.1)') jval
       !
       ! the loop over the two parities
       do irrep = 1,sym%Nrepresen
          !
          nener_total = 0
          !
          Nsym_ = Nsym(irrep)
          !
          if (Nsym_<1) cycle
          !
          if (iverbose>=3) write(out,'(/"       J      N        Energy/cm  State   v  lambda spin   sigma   omega  parity")')
          !
          if (iverbose>=4) call TimerStart('Diagonalization')
          !
          ! Prepare the Hamiltonian matrix in the symmetrized representaion
          !
          allocate(eigenval(Nsym_),hsym(Nsym_,Nsym_),stat=alloc)
          call ArrayStart('eigenval',alloc,size(eigenval),kind(eigenval))
          call ArrayStart('hsym',alloc,size(hsym),kind(eigenval))
          !
          hsym = transform(irrep)%matrix
          !
          ! Diagonalization of the hamiltonian matrix
          !
          if (iverbose>=6) write(out,'(/"Diagonalization of the hamiltonian matrix")')
          !
          select case (trim(job%diagonalizer))
            !
          case('SYEV')
            !
            call lapack_syev(hsym,eigenval)
            !
            ! we need only these many roots
            Nroots = min(job%nroots(1),Nsym_)
            !
            ! or as many as below job%upper_ener if required by the input
            if (job%upper_ener<1e8) then
              nroots = maxloc(eigenval(:)-eigenval(1),dim=1,mask=eigenval(:).le.job%upper_ener*sc)
            endif
            !
          case('SYEVR')
            !
            ! some diagonalizers needs the following parameters to be defined
            !
            jobz = 'V'
            vrange(1) = -0.0_rk ; vrange(2) = (job%upper_ener+job%ZPE)*sc
            irange(1) = 1 ; irange(2) = min(job%nroots(1),Ntotal)
            nroots = job%nroots(1)
            !
            rng = 'A'
            !
            if (irange(2)==Nsym_) then
               rng = 'A'
            elseif (irange(2)<Nsym_) then
               rng = 'I'
            elseif (job%upper_ener<1e8.and.job%upper_ener>small_) then
               rng = 'V'
            endif
            !
            !allocate(eigenval_(Ntotal),hmat_(Ntotal,Ntotal),stat=alloc)
            !
            !hmat_ = hmat
            !
            !call lapack_syev(hmat_,eigenval_)
            !
            !call lapack_syevr(hmat_,eigenval_,rng=rng,jobz=jobz,iroots=nroots,vrange=vrange,irange=irange)
            !
            !eigenval_ = eigenval_/sc
            !
            !
            !deallocate(hmat_,eigenval_)
            !
            call lapack_syevr(hsym,eigenval,rng=rng,jobz=jobz,iroots=nroots,vrange=vrange,irange=irange)
            !
            !
          case default
            !
            print "('Unrecognized diagonalizer ',a)", trim(job%diagonalizer)
            stop  'Unrecognized diagonalizer'
            !
          end select
          !
          !
          if (iverbose>=6) write(out,'("...done!")')
          !
          if (iverbose>=4) call TimerStop('Diagonalization')
          !
          ! The ZPE value can be obtained only for the first J in the J_list tau=1.
          ! Otherwise the value from input must be used.
          if (irot==1.and.irrep==1.and.abs(job%ZPE)<small_.and.iverbose/=0) then
            !
            job%ZPE = eigenval(1)/sc
            !
            if (action%intensity) intensity%ZPE = job%ZPE
            !
          endif
          !
          eigenval(:) = eigenval(:)/sc
          !
          if (iverbose>=4) call TimerStart('Assignment')
          !
          ! Assign the eigevalues with quantum numbers and print them out
          !
          !omp parallel do private(i,mterm,f_t,plusminus) shared(maxTerm) schedule(dynamic)
          do i=1,Nroots
            !
            ! to get the assignement we find the term with the largest contribution
            !
            j = maxloc(hsym(:,i)**2,dim=1,mask=hsym(:,i)**2.ge.small_)
            !
            mlevel = transform(irrep)%irec(j)
            mterm = ilevel2i(mlevel,irrep)
            !
            istate = icontr(mterm)%istate
            sigma = icontr(mterm)%sigma
            imulti = icontr(mterm)%imulti
            ilambda = icontr(mterm)%ilambda
            omega = icontr(mterm)%omega
            spini = icontr(mterm)%spin
            v = icontr(mterm)%v
            !
            if (iverbose>=3) write(out,'(2x,f8.1,i5,f18.6,1x,i3,2x,2i4,3f8.1,3x,a1,4x,"||",a)') & 
                             jval,i,eigenval(i)-job%ZPE,istate,v,ilambda,spini,sigma,omega,plusminus(irrep), &
                                                  trim(poten(istate)%name)
            !
            ! do not count degenerate solutions
            !
            if (i>1.and.abs( eigenval(i)-eigenval(max(i-1,1)) )<job%degen_threshold) cycle
            !
            nener_total = nener_total + 1
            !
            ! for fitting we will need the energies and quantum numbers as a result of this subroutine
            !
            if (present(enerout)) then
               if (nener_total<=size(enerout,dim=3)) then
                  enerout(irot,irrep,nener_total) = eigenval(i)
               endif
            endif
            !
            if (present(quantaout)) then
               if (nener_total<=size(enerout,dim=3)) then
                  !
                  quantaout(irot,irrep,nener_total)%Jrot = Jval
                  quantaout(irot,irrep,nener_total)%irot = irot
                  quantaout(irot,irrep,nener_total)%istate = istate
                  quantaout(irot,irrep,nener_total)%sigma = sigma
                  quantaout(irot,irrep,nener_total)%imulti = imulti
                  quantaout(irot,irrep,nener_total)%ilambda = ilambda
                  quantaout(irot,irrep,nener_total)%omega = omega
                  quantaout(irot,irrep,nener_total)%spin  = spini
                  quantaout(irot,irrep,nener_total)%v = v
                  quantaout(irot,irrep,nener_total)%iparity = irrep-1
                  !
               endif
            endif
          enddo
          !
          if (iverbose>=4) call TimerStop('Assignment')
          !
          if (action%intensity) then
            !
            ! total number of levels for given J,gamma selected for the intensity calculations
            total_roots = 0
            !
            if (iverbose>=4) call TimerStart('Prepare_eigenfuncs_for_intens')
            !
            do i=1,Nroots
              !
              call Energy_filter(Jval,eigenval(i),irrep,passed)
              !
              if (passed) total_roots = total_roots + 1
              !
            enddo
            !
            total_roots = max(total_roots,1)
            !
            allocate(eigen(irot,irrep)%vect(Ntotal,total_roots),eigen(irot,irrep)%val(total_roots), & 
                               eigen(irot,irrep)%quanta(total_roots),stat=alloc)
            call ArrayStart('eigens',alloc,size(eigen(irot,irrep)%vect),kind(eigen(irot,irrep)%vect))
            call ArrayStart('eigens',alloc,size(eigen(irot,irrep)%val),kind(eigen(irot,irrep)%val))
            !
            allocate(basis(irot)%icontr(Ntotal),stat=alloc)
            !
            do i=1,Ntotal
              !
              basis(irot)%icontr(i)%istate = icontr(i)%istate
              basis(irot)%icontr(i)%sigma  = icontr(i)%sigma
              basis(irot)%icontr(i)%ilambda= icontr(i)%ilambda
              basis(irot)%icontr(i)%spin   = icontr(i)%spin
              basis(irot)%icontr(i)%omega  = real(icontr(i)%ilambda,rk)+icontr(i)%sigma
              basis(irot)%icontr(i)%ivib   = icontr(i)%ivib
              !
            enddo
            !
            basis(irot)%Ndimen = Ntotal
            !
            total_roots = 0
            !
            eigen(irot,irrep)%Nlevels = 0
            eigen(irot,irrep)%Ndimen = Ntotal
            !
            do i=1,Nroots
              !
              call Energy_filter(Jval,eigenval(i),irrep,passed)
              !
              if (passed) then  
                !
                vec = 0
                !
                do isym = 1,Nsym_
                  !
                  ilevel = transform(irrep)%irec(isym)
                  !
                  do jrrep = 1,sym%Nrepresen
                    !
                    do itau=1,Nirr(ilevel,jrrep)
                      !
                      k = ilevel2i(ilevel,jrrep)
                      !
                      jsym = ilevel2isym(ilevel,irrep)
                      !
                      vec(k) = vec(k) + hsym(isym,i)*Utransform(ilevel,jrrep,irrep)
                      !
                    enddo
                    !
                  enddo
                  !
                enddo
                !
                total_roots = total_roots + 1
                !
                ! to get the assignement we find the term with the largest contribution
                !
                j = maxloc(hsym(:,i)**2,dim=1,mask=hsym(:,i)**2.ge.small_)
                mlevel = transform(irrep)%irec(j)
                mterm = ilevel2i(mlevel,irrep)
                !
                istate = icontr(mterm)%istate
                sigma = icontr(mterm)%sigma
                imulti = icontr(mterm)%imulti
                ilambda = icontr(mterm)%ilambda
                omega = icontr(mterm)%omega
                spini = icontr(mterm)%spin
                v = icontr(mterm)%v
                !
                eigen(irot,irrep)%vect(:,total_roots) = vec(:)
                eigen(irot,irrep)%val(total_roots) = eigenval(i)
                eigen(irot,irrep)%quanta(total_roots)%istate = istate
                eigen(irot,irrep)%quanta(total_roots)%sigma = sigma
                eigen(irot,irrep)%quanta(total_roots)%imulti = imulti
                eigen(irot,irrep)%quanta(total_roots)%ilambda = ilambda
                eigen(irot,irrep)%quanta(total_roots)%omega = omega
                eigen(irot,irrep)%quanta(total_roots)%spin = spini
                eigen(irot,irrep)%quanta(total_roots)%iparity = irrep-1
                eigen(irot,irrep)%quanta(total_roots)%igamma = irrep
                eigen(irot,irrep)%quanta(total_roots)%v = v
                eigen(irot,irrep)%quanta(total_roots)%name = trim(poten(istate)%name)
                !
              endif
              !
            enddo
            !
            eigen(irot,irrep)%Nlevels = total_roots
            !
            if (iverbose>=4) call TimerStop('Prepare_eigenfuncs_for_intens')
            !
          endif
          !
          deallocate(hsym,eigenval)
          call ArrayStop('hsym')
          call ArrayStop('eigenval')
          !
          if (present(nenerout)) nenerout(irot,irrep) = nener_total
          !
       enddo
       !
       if (iverbose>=2) write(out,'(/"Zero point energy (ZPE) = ",f18.6)') job%ZPE
       !
       !omp end parallel do
       !
       !jval = jval + 1.0_rk ; irot = irot + 1
       !
       deallocate(iswap,vec,Nirr)
       call ArrayStop('iswap-vec')
       call ArrayStop('Nirr')
       !
       deallocate(ilevel2i,tau,ilevel2isym)
       !
       deallocate(transform(1)%matrix,transform(2)%matrix,transform(1)%irec,transform(2)%irec)
       call ArrayStop('transform')
       !
       deallocate(Utransform)
       call ArrayStop('Utransform')
       !
       deallocate(hmat)
       call ArrayStop('hmat')
       !
       deallocate(printout)
       !
       deallocate(ivib_level2icontr,icontr)
       call ArrayStop('ivib_level2icontr')
       !
     enddo loop_jval
     !
     deallocate(J_list)
     !
     deallocate(contrenergy)
     call ArrayStop('contrenergy')
     !
  end subroutine duo_j0


 !
 subroutine Energy_filter(Jval,energy,igamma,passed)
   !
   real(rk),intent(in)    :: Jval,energy
   integer(ik),intent(in) :: igamma
   logical,intent(out)    :: passed
   real(rk)               :: erange(2)
     !
     ! passed = .true.
     !
     ! if (.not.intensity%do) return
     !
     passed = .false.
     erange(1) = min(intensity%erange_low(1),intensity%erange_upp(1))
     erange(2) = max(intensity%erange_low(2),intensity%erange_upp(2))
     !
     if (job%isym_do(igamma).and.energy-job%ZPE>=erange(1).and.  &
         Jval>=intensity%J(1).and.Jval<=intensity%J(2).and.&
         energy-job%ZPE<=erange(2)) then 
         !
         passed = .true.
         !
     endif 

 end subroutine Energy_filter


  function three_j(a,b,c,al,be,ga)

      real(rk) :: three_j
      real(rk),intent(in) :: a,b,c,al,be,ga
      !
      integer(ik):: newmin,newmax,new,iphase
      real(rk)   :: delta,clebsh,minus
      real(rk)   :: term,term1,term2,term3,summ,dnew,term4,term5,term6,delta_log,term16,termlog


      three_j=0
!
!     (j1+j2).ge.j and j.ge.abs(a-b)    -m=m1+m2    j1,j2,j.ge.0
!     abs(m1).le.j1    abs(m2).le.j2   abs(m).le.j
!
      if(c.gt.a+b) return
      if(c.lt.abs(a-b)) return
      if(a.lt.0.or.b.lt.0.or.c.lt.0) return
      if(a.lt.abs(al).or.b.lt.abs(be).or.c.lt.abs(ga)) return
      if(-1.0_rk*ga.ne.al+be) return
!
!
!     compute delta(abc)
!
!     delta=sqrt(fakt(a+b-c)*fakt(a+c-b)*fakt(b+c-a)/fakt(a+b+c+1.0_rk))
      delta_log = faclog(a+b-c)+faclog(a+c-b)+faclog(b+c-a)-faclog(a+b+c+1.0_rk)
      !
      delta=sqrt(exp(delta_log)) 
!
!
      !term1=fakt(a+al)*fakt(a-al)
      !term2=fakt(b-be)*fakt(b+be)
      !term3=fakt(c+ga)*fakt(c-ga)
      !
      !term=sqrt( (2.0_rk*c+1.0_rk)*term1*term2*term3 )
      !
      !
      term1=faclog(a+al)+faclog(a-al)
      term2=faclog(b-be)+faclog(b+be)
      term3=faclog(c+ga)+faclog(c-ga)
      !
      termlog = ( term1+term2+term3+delta_log )*0.5_rk
 
      term=sqrt( (2.0_rk*c+1.0_rk) )
!
!
!     now compute summation term
!
!     sum to get summation in eq(2.34) of brink and satchler.  sum until
!     a term inside factorial goes negative.  new is index for summation
!     .  now find what the range of new is.
!
!
      newmin=idnint(max((a+be-c),(b-c-al),0.0_rk))
      newmax=idnint(min((a-al),(b+be),(a+b-c)))
!
!
      summ=0
!
!
      do new=newmin,newmax
        !
        dnew=real(new,rk)
        !
        term4=faclog(a-al-dnew)+faclog(c-b+al+dnew)
        term5=faclog(b+be-dnew)+faclog(c-a-be+dnew)
        term6=faclog(dnew)+faclog(a+b-c-dnew)
        !
        term16=termlog-(term4+term5+term6)
        !
        summ=summ+(-1.0_rk)**new*exp(term16)
        !
      enddo
!
!     so clebsch-gordon <j1j2m1m2ljm> is clebsh
!
      clebsh=term*summ ! /sqrt(10.0_rk)
!
!     convert clebsch-gordon to three_j
!
      iphase=idnint(a-b-ga)
      minus = -1.0_rk
      if (mod(iphase,2).eq.0) minus = 1.0_rk
      three_j=minus*clebsh/term

!     threej=(-1.d0)**(iphase)*clebsh/sqrt(2.0_rk*c+1.d0)
!
!
   end function three_j
  !
  !
  ! calculate factorial by log function 
  ! 
  function faclog(a)   result (v)
    real(rk),intent(in) ::  a
    real(ark)              :: v 
    integer(ik) j,k

    v=0
    k=nint(a)
    if(k>=2) then 
      do j=2,k
         v=v+log(real(j,ark))
      enddo 
    endif 
    
  end function faclog
  !
end module diatom_module



