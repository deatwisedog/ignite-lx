Ignite-LX (Linux disaster recovery)
===================================

1.) What is Ignite-LX

	Ignite-LX is a free disaster recovery script framework which
	enables you to recovery a you Linux Box. This toolset is based
	on the ideas from HP-UX Ignit-UX.
	The latest version is available:
	http://ignite-lx.powercore.org


2.) Requirement

	Ignite-LX requires the package / binary:

	ip (iproute)
	genisoimage



3.) How does it work

	Ignite-LX collect all relevant system informations like disks, lvm, raid, 
	network, etc. and create a compressed cpio archive from system. There are various 
	scripts they do this work. The result will be a bootable "ISO" image and
	a "Kernel + Initrd set" (this can be used for netboot PXE, exp. by Cobbler)
	and a archive of your system.
	The "ISO" or "Kernel + Initrd" contains not all files to restore the system,
	it contains only a mini live system to run the recovery (menu based). Only
	the compressed cpio archive contains all relevant OS files and "this location"
	is also included in "ISO", etc. boot set.

	Ignite-LX supports multibel "backends" for disaster recovery image
	creation and restore. At the moment there is only one backend
	available it's called "nfs". NFS backend enables the creation and restore
	of your Linux Box via a NFS Share. In the features I'll develop a "http", "sftp"
	and "file" backend.



4.) How to install

	There is no installation package builded at the moment. Simply 
	extract the "ignite-lx.tar.gz" into "/opt" directory, thats all.
	If you want to use a other target directory you have to set a
	environment variable "IGX_BASE" pointed to the "ignite-lx" directory.
	
	Example: export IGX_BASE="$HOME/ignite-lx"

	The Ignite-LX comes with following default directories:

	bin			# contains the make_recovery.sh for image creation
	bin/backup/backends	# contains available backup backends
	bin/common		# contains major function and helper scripts
	bin/restore/backends	# contains available restore backends
	data/boot64/image	# local location of created ISO, initrd and kernel (64 bit)
	data/boot64/initrd_root	# contains relevant live system files for restore (64 bit)
	data/boot64/iso_root	# file required for boot (ISO) creation (64 bit)
	data/config		# local location of all create recovery sets (system infos.)
	etc			# contains ignite.conf for all ignite and "backend" setting
	log			# contains ignite.log (created if a backup is started)
	mnt/arch_mnt		# backend "nfs" default share mountpoint folder



5.) How to use Ignite-LX (create a disaster recovery image)

	Ignite-LX is just simple to run. For the end user finally only the run of
	one script is required. This script is called "make_recovery.sh" and
	is located in the "bin" directory of ignite-lx folder.
	Additional there are some autarky work/help scripts, located in directory bin/common.

	Overview os scripts relevant files:

	bin/common/ignite_common.inc	# major framework functions (include in scripts)
	bin/common/make_boot.sh		# create the ignited (live system) + iso
	bin/common/make_config.sh	# collect the required restore informations
	bin/common/make_image.sh	# create the compressed cpio system archive
	bin/make_recovery.sh		# END USER SCRIPT TO CREATE BACKUP
	bin/restore/edit_restore.sh	# used in live system restore to edit restore info.
	bin/restore/make_restore.sh	# restore the system if live system is booted
	bin/restore/run_restore.sh	# run the restore GUI menu in live system
	etc/ignite.conf			# contains all ignite + backend settings

	To create a system disaster recovery image see the following example below:

	-	On a secondary system (called "backupsrv" in this example) export a "root" writeable
		share, for example "/var/ignite" and create a client folder which should used for
		backup.

		# mkdir -p /var/ignite/linuxbox
		# echo "/var/ignite linuxbox(rw,no_root_squash,sync,subtree_check)" >> /etc/exports
		# exportfs -a

	- 	On the system which should backup'd edit the etc/ignite.conf

		# vi /etc/ignite.conf
		#
		# NFS Backend configuration
		#
		IGX_NFS_URL="backupsrv:/var/ignite/linuxbox"
		IGX_NFS_MOUNTPOINT="$IGX_BASE/mnt/arch_mnt"

	-	Now run the recovery script as followed and be sure, that all devices or VolumeGroups
		required to run your OS (NOT THE EXTERNAL DISKS) are included 
		(see script help for details).

		# cd /opt/ignite-lx/bin
		# ./make_recovery.sh -b nfs -i vg00 -i /dev/md0 -x /tmp -x /var/tmp -x /wwwroot


		The switches does the following:

		-i <dev/vg> include the device or VolumeGroup which should include in backup
		-x <directory> the defined directory is excluded from backup
		-b <backend> define the backend used for backup creation

		Explain of switches:

		The system "linuxbox" has following mountpoints:

		/dev/md0 on / type xfs (rw)
		/dev/mapper/vg00-lv_home on /home type xfs (rw)
		/dev/mapper/vg00-lv_opt on /opt type xfs (rw)
		/dev/mapper/vg00-lv_tmp on /tmp type xfs (rw)
		/dev/mapper/vg00-lv_usr on /usr type xfs (rw)
		/dev/mapper/vg00-lv_local on /usr/local type xfs (rw)
		/dev/mapper/vg00-lv_var on /var type xfs (rw)

		The moutpoints above are native OS mountpoints and required in a backup.
		The "make_recovery.sh" script resolve the mountpoints by devices and
		VolumeGroups so we have to define "/dev/md0" for root mountpoint and
		"vg00" for VolumeGroup called "vg00". 

		Note: All VolumeGroup LVs are automatically included!
		
