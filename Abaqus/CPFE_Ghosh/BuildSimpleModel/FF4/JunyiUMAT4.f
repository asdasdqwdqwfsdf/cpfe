      SUBROUTINE UMAT(stress,statev,ddsdde,sse,spd,scd,
     1 rpl, ddsddt, drplde, drpldt,
     2 stran,dstran,time,dtime,temp,dtemp,predef,dpred,cmname,
     3 ndi,nshr,ntens,nstatv,props,nprops,coords,drot,pnewdt,
     4 celent,dfgrd0,dfgrd1,noel,npt,layer,kspt,kstep,kinc)
	 
      include 'aba_param.inc'
c
#include <SMAAspUserSubroutines.hdr>
      CHARACTER*8 CMNAME
      EXTERNAL F

      dimension stress(ntens),statev(nstatv),
     1 ddsdde(ntens,ntens),ddsddt(ntens),drplde(ntens),
     2 stran(ntens),dstran(ntens),time(2),predef(1),dpred(1),
     3 props(nprops),coords(3),drot(3,3),dfgrd0(3,3),dfgrd1(3,3)
	 
      include 'DeclareParameterSlipsO.f'
      
      INTEGER:: ISLIPS, I, J, NDUM1, NA, NB, ICOR, ISL
      real*8 :: TAU(18), TAUPE(12), TAUSE(12), TAUCB(12)
      real*8 :: SLIP_T(54), IBURG	  
      real*8 :: RhoP(18),RhoF(18),RhoM(18),RhoSSD(18)
      real*8 :: TauPass(18), TauCut(18), V0(18)
      real*8 :: H(12), RhoCSD(12), TAUC(18) 
      real*8 :: Vs(18) , GammaDot(18) , TauEff(18), SSDDot(18)
      real*8 :: DStress(6) , KCURLLOCAL(6)
	  
      real*8 :: ORI_ROT(3,3), SPIN_TENSOR(3,3)
      real*8:: dFP(9), dRhoS(18),dRhoET(18),dRhoEN(18)
c ------------------------------------------------	  
C
C     CALCULATE VELOCITY GRADIENT FROM DEFORMATION GRADIENT.
C     REFERENCE: Li & al. Acta Mater. 52 (2004) 4859-4875
C     
      real*8,parameter  :: zero=1.0e-16,xgauss = 0.577350269189626
      real*8,parameter  :: xweight = 1.0
      integer, parameter :: TOTALELEMENTNUM=853200
      Real*8:: FTINV(3,3),STRATE(3,3),VELGRD(3,3),AUX1(3,3),ONEMAT(3,3)
      PARAMETER (ONE=1.0D0,TWO=2.0D0,THREE=3.0D0,SIX=6.0D0)
      DATA NEWTON,TOLER/10,1.D-6/
      Real*8:: gausscoords(3,8)
      real*8 :: kgausscoords, kFp, kcurlFp
      real*8:: xnat(20,3),xnat8(8,3),gauss(8,3), DGA(18)
      real*8:: svars(48)
c XDANGER
      COMMON/UMPS/kgausscoords(TOTALELEMENTNUM,8,3),
     1 kFp(TOTALELEMENTNUM,8, 3),
     1 kcurlFp(TOTALELEMENTNUM, 8, 3)
	  
c      print *, '*****************************************'

C +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
c PROPS  Definitions
c
c PROPS(1->9) :: Orientation Matrix
c PROPS(1->27) :: Rho_SSD Initial
c PROPS(28->48) :: Compliance Matrix in Voigt Notation

c PROPS(49) :: TYPE (NOT USED)

c Note that these properties were precalculated so they don't have to be repeatedly calculated

c GetRhoPFMGND
c PROPS(50) :: (1) :: c_10 * kB * Theta / (G * b^2)

c GetTauSlips
c PROPS(51) :: (1) :: c_3 * G * b
c PROPS(52) :: (2) :: c_4 * kB * Theta/ (b^2)
c PROPS(53) :: (3) :: c_1 * (Theta ^ (c_2))

c GetCSDHTauC
c PROPS(54) :: (1) :: b / Gamma_111
c PROPS(55) :: (2) :: G * b^3 / (4 * pi)
c PROPS(56) :: (3) :: G * b^2 / (2 * pi * Gamma_111)
c ** PROPS(57) :: (4) ::  xi * G * b = xi_0 * exp(A/(Theta-Theta_c)) * G * b
c ** PROPS(58) :: (5) :: tau_cc
c PROPS(59) :: (6) :: C_H
c PROPS(60) :: (7) ::  h
c PROPS(61) :: (8) :: k_1
c PROPS(62) :: (9) :: k_2
c PROPS(63) :: (10) :: (1/sqrt(3)) - Gamma_010 / Gamma_111
c ** PROPS(64) :: (11) :: b / B
c ** PROPS(65) :: (12) :: rho_0
c PROPS(66) :: (13) :: kB * Theta 

c GetGammaDot
c PROPS(67) :: (1) :: exp(-Q / (kB * Theta))
c PROPS(68) :: (2) :: p
c PROPS(69) :: (3) :: b
 
c GetRhoSSDEvolve
c PROPS(70) :: (1) :: c_5 / b
c PROPS(71) :: (2) :: (c_6 / b) * (sqrt(3) * G * b)/ (16 * (1-nu))
c PROPS(72) :: (3) :: c_7
c PROPS(73) :: (4) :: c_8 * ( (D_0 b^3) / (kB * Theta) ) * exp(- Q_Bulk / (kB * Theta)))
c PROPS(74) :: (5) :: c_9
c PROPS(75) :: (6) :: gamma_dot_ref

c No Longer In Use
c PROPS(76) :: (1) :: c_11
c PROPS(77) :: (2) :: c_12
c PROPS(78) :: (3) :: c_44

c No Longer In Use
c PROPS(79) :: (1) :: rho_ssd 

C +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
c SDV  Definitions
c
C SDV(1->54) :: Slip direction ((ISLIP-1)*3+COMPONENT)
C SDV(55->108) :: Slip normals ((ISLIP-1)*3+COMPONENT)+OFFSET
C SDV(109->126) :: Rho SSD (ISLIP)
C SDV(127->144) :: Rho CSD (ISLIP)

C SDV(145->162) :: Gamma Slip cumulative
c SDV(163) :: Cumulative gamma slip
c SDV(164->184) :: Compliance Matrix

c SDV(185->220) ::  Slip direction PE ((ISLIP-1)*3+COMPONENT)+OFFSET
c SDV(221->256) ::  Slip normals PE ((ISLIP-1)*3+COMPONENT)+OFFSET
c SDV(257->292) ::  Slip direction SE ((ISLIP-1)*3+COMPONENT)+OFFSET
c SDV(293->328) ::  Slip normals SE ((ISLIP-1)*3+COMPONENT)+OFFSET
c SDV(329->364) ::  Slip direction CB ((ISLIP-1)*3+COMPONENT)+OFFSET
c SDV(365->400) ::  Slip normals CB ((ISLIP-1)*3+COMPONENT)+OFFSET

c SDV(401->409) :: Plastic Deformation Tensor
c SDV(410->427) :: Rho GND S (SLIP)
c SDV(428->429) :: Nothing Made a mistake here previously
c SDV(430->447) :: Rho GND ET (SLIP)
c SDV(448->465) :: Rho GND EN (SLIP)

c *********************************************
c Code starts here	
      CALL ONEM(ONEMAT)     
      CALL ZEROM(FTINV)
      CALL ZEROM(AUX1)
      CALL ZEROM(VELGRD)
      CALL M3INV(DFGRD0,FTINV)
      CALL MPROD(DFGRD1,FTINV,AUX1)
      DO 231 I=1,3
        DO 231 J=1,3
          VELGRD(I,J) = (AUX1(I,J)-ONEMAT(I,J))
231   CONTINUE	
 
      DO I=1,3
       DO J=1,3
	      SPIN_TENSOR(I,J)=0.5*(VELGRD(I,J)-VELGRD(J,I))
       END DO
      END DO	
c ------------------------------------------------		
c Perform Initialisation

      IF (KINC.LE.1) THEN
	  
       DO ISLIPS=1,nstatv
          STATEV(ISLIPS)=0.0
       END DO

       NDUM1=0
       DO I=1,3
       DO J=1,3
          NDUM1=NDUM1+1
          ORI_ROT(I,J)=PROPS(NDUM1)
       END DO
       END DO
	   
       DO ISLIPS=1,18
          STATEV(ISLIPS+108)=PROPS(ISLIPS+9)
       END DO

c ---- S_SCHMID
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_S0(1:3,ISLIPS),STATEV(NA:NB))
       END DO
       DO ISLIPS=1,6
        NDUM1=(ISLIPS+11)*3
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,CUBIC_S0(1:3,ISLIPS),STATEV(NA:NB))
       END DO

c ---- N_SCHMID
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+54
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_N0(1:3,ISLIPS),STATEV(NA:NB))
       END DO
       DO ISLIPS=1,6
        NDUM1=(ISLIPS+11)*3+54
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,CUBIC_N0(1:3,ISLIPS),STATEV(NA:NB))
       END DO	
	   
c ---- S_PE
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+184
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_SPE0(1:3,ISLIPS),STATEV(NA:NB))
       END DO
c ---- N_PE
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+220
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_NPE0(1:3,ISLIPS),STATEV(NA:NB))
       END DO

c ---- S_SE
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+256
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_SSE0(1:3,ISLIPS),STATEV(NA:NB))
       END DO
c ---- N_SE
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+292
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_NSE0(1:3,ISLIPS),STATEV(NA:NB))
       END DO	   
	   
c ---- S_CB
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+328
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_SCB0(1:3,ISLIPS),STATEV(NA:NB))
       END DO
c ---- N_CB
       DO ISLIPS=1,12
        NDUM1=(ISLIPS-1)*3+364
        NA=NDUM1+1
        NB=NDUM1+3		        
        call ROTATE_Vec(ORI_ROT,FCC_NCB0(1:3,ISLIPS),STATEV(NA:NB))
       END DO	      
c ---- Rotate STIFFNESS TENSOR
        call ROTATE_COMTEN(ORI_ROT,PROPS(28:48),STATEV(164:184))

c--- Do Stuff
       STATEV(401)=1.0
       STATEV(405)=1.0
       STATEV(409)=1.0

c XDANGER
       DO ISLIPS=1,18
        STATEV(409+ISLIPS)=(1.0e9)*(1.0e-12)
        STATEV(429+ISLIPS)=(1.0e9)*(1.0e-12)
        STATEV(447+ISLIPS)=(1.0e9)*(1.0e-12) 
       END DO	 
c      DO ISLIPS=1,6
c        STATEV(271+ISLIPS)=0.0
c        STATEV(289+ISLIPS)=0.0
c        STATEV(307+ISLIPS)=0.0   
c       END DO	
	   
      call MutexLock( 2 )      ! lock Mutex #2      
      ! use original co-ordinates X     
      do i =1,3
          kgausscoords(noel,npt,i) = coords(i)
      end do
      call MutexUnlock( 2 )   ! unlock Mutex #2
		
		
      ENDIF
c --------------------------------
C Calculate som common values
        call Get_TfromSN(STATEV(1:54),STATEV(55:108),SLIP_T)

c ------------------------------------------------	
c NOW FOR THE MAIN STUFF
        call CalculateTauS(STRESS, TAU, TAUPE, TAUSE, TAUCB,
     +  STATEV(1:54), STATEV(55:108),
     +  STATEV(185:220), STATEV(221:256),
     +  STATEV(257:292), STATEV(293:328),
     +  STATEV(329:364), STATEV(365:400))	

       call GetRhoPFMGND(RhoP,RhoF,RhoM,
     1 STATEV(109:126),
     2 STATEV(1:54),STATEV(55:108),SLIP_T,
     2 STATEV(410:427),STATEV(430:447),STATEV(448:465),
     5 PROPS(50))
	 
        call GetTauSlips(RhoP,RhoF,RhoM,
     1 TauPass, TauCut, V0,	  
     2 PROPS(51:53))
	 
      call GetCSDHTauC(TAUPE,TAUSE,TAUCB,
     1 H, RhoCSD, TAUC, 	   
     2 PROPS(54:66))	 

      call GetGammaDot(Tau, TauPass, TauCut, V0, RhoM, 
     1 Vs, GammaDot, TauEff, TAUC,	    	   
     2 PROPS(67:69))	 	 

C-DBG	 
c      DO ISLIPS=1,18  
c		GammaDot(ISLIPS)=0.0
c      END DO	
	 
      call GetRhoSSDEvolve(Tau, TauPass, TauCut, V0, RhoM, 
     1 GammaDot, TauEff, SSDDot, STATEV(109:126), RhoF,      	   
     2 PROPS(70:75))

      call GetDSTRESSFP(DStress,GammaDot,dstran,Stress,dTIME, 
     1 STATEV(1:54),STATEV(55:108), dFP, STATEV(401:409),
     2 STATEV(164:184))

      call GetDDSDDE(DDSDDE,Stress,	   
     2 STATEV(164:184))
	 
c ------------------------------------------------	
c UPDATE ALL
      DO ISLIPS=1,18  
		DGA(ISLIPS)=DTIME*GammaDot(ISLIPS)
      END DO	
	  
      DO ISLIPS=1,18
       STATEV(ISLIPS+108)=STATEV(ISLIPS+108)+DTIME*SSDDot(ISLIPS)
       STATEV(ISLIPS+144)=STATEV(ISLIPS+144)+DGA(ISLIPS)
       STATEV(163)=STATEV(163)+abs(DGA(ISLIPS))
      END DO
      DO ISLIPS=1,6
       Stress(ISLIPS)=Stress(ISLIPS)+DStress(ISLIPS)	
      END DO
      DO ISLIPS=1,12
       STATEV(ISLIPS+126)=RhoCSD(ISLIPS)	
      END DO
c ------------------------------------------------	
c Rotate The Slip Systems

c ---- S
c      call RotateSlipSystems(GammaDot,dTIME,DSTRAN, SPIN_TENSOR,
c     1 STATEV(1:54),STATEV(55:108),
c     +  STATEV(185:220), STATEV(221:256),
c     +  STATEV(257:292), STATEV(293:328),
c     +  STATEV(329:364), STATEV(365:400))

c ------------------------------------------------	
         DO kint =1,8 
             DO i=1,3         
                 gausscoords(i,kint) = kgausscoords(noel,kint,i)                          
             END DO 
         END DO

c--------------------------------------------------
c Calculate dRHO  
      INCLUDE 'kgauss2.f'     
      xnat8 = xnat(1:8,:) 			 
      IBURG=1.0/PROPS(69)
	  
      DO ISLIPS=1,18  
		     dRhoS(ISLIPS)=0.0
		     dRhoET(ISLIPS)=0.0
		     dRhoEN(ISLIPS)=0.0
      ENDDO	  
	  
c calculate GammadotFPnalpha	 
      DO ISLIPS=1,18  
c       write(6,*) "CP1---------------------------"
       call MutexLock( 1 )      ! lock Mutex #1 
       DO i=1,3                                                      
        kFp(noel,npt,i)= 0.0
       END DO
	   
       DO i=1,3      
       DO j=1,3  	   
c	    ICOR=400+(J-1)*3+I
	    ICOR=400+(I-1)*3+J
		ISL=(ISLIPS-1)*3+J+54
        kFp(noel,npt,i)= kFp(noel,npt,i)+DGA(ISLIPS)*
     1   IBURG*STATEV(ICOR)*STATEV(ISL)
       END DO	 
       END DO
	   
        call MutexUnlock( 1 )      ! lock Mutex #1 
		
c       write(6,*) "CP2"		
         DO kint =1,8 
             DO i=1,3         
                 gausscoords(i,kint) = kgausscoords(noel,kint,i)                          
             END DO
         
             DO i=1,3          
                 svars(i + 6*(kint-1)) = kFp(noel,kint,i)         
             END DO
         END DO	 		
c       write(6,*) "CP3"				
        call VectorCurl(svars,xnat8,gauss,gausscoords) 		
c       write(6,*) "CP4"				
      call MutexLock( 3 )      ! lock Mutex #1 
      DO kint =1, 8
          DO i=1, 3
              kcurlFp(noel,kint,i) = svars(3+i + 6*(kint-1))
          END DO
      END DO
      call MutexUnlock( 3 )      ! lock Mutex #1 
	  
c       write(6,*) "CP5"		
      DO i=1,3
          KCURLLOCAL(3+I) = kcurlFp(noel,npt,i)
		  KCURLLOCAL(I) = kFp(noel,npt,i) 

c		  ICOR=(ISLIPS-1)*6
c		  STATEV(I+522+ICOR)= kcurlFp(noel,npt,i) 
c		  STATEV(I+519+ICOR)= kFp(noel,npt,i) 		  
      END DO
c       write(6,*) "CP6"		

      DO i=1,3	  
	      ICOR=3*(ISLIPS-1)+I
          dRhoS(ISLIPS)=dRhoS(ISLIPS)+
     1 (STATEV(ICOR)*KCURLLOCAL(3+I))
          dRhoET(ISLIPS)=dRhoET(ISLIPS)+
     1 (SLIP_T(ICOR)*KCURLLOCAL(3+I))
          dRhoEN(ISLIPS)=dRhoEN(ISLIPS)+
     1 (STATEV(ICOR+54)*KCURLLOCAL(3+I))
      END DO	  
c       write(6,*) "CP7=",ISLIPS
      END DO
		 
c--------------------------------------------------		 
         DO ISLIPS=1,9
		     STATEV(400+ISLIPS)=STATEV(400+ISLIPS)+dFP(ISLIPS)
         END DO		 

         DO ISLIPS=1,18
c		     STATEV(409+ISLIPS)=STATEV(409+ISLIPS)+dRhoS(ISLIPS)
c		     STATEV(429+ISLIPS)=STATEV(429+ISLIPS)+dRhoET(ISLIPS)
c		     STATEV(447+ISLIPS)=STATEV(447+ISLIPS)+dRhoEN(ISLIPS)		

		     IF (STATEV(409+ISLIPS).LE.0.0) THEN
		        STATEV(409+ISLIPS)=0.0
		     ENDIF
		     IF (STATEV(429+ISLIPS).LE.0.0) THEN
		        STATEV(429+ISLIPS)=0.0
		     ENDIF
		     IF (STATEV(447+ISLIPS).LE.0.0) THEN
		        STATEV(447+ISLIPS)=0.0
		     ENDIF			 
c		     STATEV(465+ISLIPS)=STATEV(465+ISLIPS)+dRhoS(ISLIPS)
c		     STATEV(483+ISLIPS)=STATEV(483+ISLIPS)+dRhoET(ISLIPS)
c		     STATEV(501+ISLIPS)=STATEV(501+ISLIPS)+dRhoEN(ISLIPS)		

			 
         END DO		

c  -----------------------------------
      DO ISLIPS=1,6
       IF ((ABS(DStress(ISLIPS)).LT.5.0e1)) THEN
       ELSE
         PNEWDT=0.5
       END IF	   
      END DO		

      DO ISLIPS=1,18
       IF ((ABS(DGA(ISLIPS)).LT.1.0e-4)) THEN
       ELSE
         PNEWDT=0.5
       END IF	   
      END DO		  
c ------------------------------------------------	 


c      DO ISLIPS=1,18  
c		STATEV(530+ISLIPS)=TAU(ISLIPS)
c		STATEV(549+ISLIPS)=TAUC(ISLIPS)
c		STATEV(567+ISLIPS)=TAUPASS(ISLIPS)
c		STATEV(585+ISLIPS)=TAUCUT(ISLIPS)
c		STATEV(603+ISLIPS)=TAUEFF(ISLIPS)
c      END DO	

      return
      end subroutine UMAT

      include 'UTILS1.f'
      include 'StiffnessTensorTools.f'
      include 'CalculateTauS.f'
      include 'GetRhoPFMGND.f'
      include 'GetTauSlips.f'
      include 'GetCSDHTauC.f' 
      include 'GetGammaDot.f'
      include 'GetRhoSSDEvolve.f'
      include 'GetDSTRESS2FP.f'	
      include 'GetDDSDDEN.f'
      include 'VectorProjections.f'
      include 'RotateSlipSystems.f'
	  
      include 'VectorCurl.f'	  	  
      include 'CalculateDRhoDBG.f'	  
      include 'kshapes.f'
      include 'utils.f'
      include 'uexternaldb.f'