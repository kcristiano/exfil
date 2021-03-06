#!/usr/local/bin/bash
#
#
#		    .-''-.   _____     __   ________ .-./`)   .---.
#		  .'_ _   \  \   _\   /  / |        |\ .-.')  | ,_|
#		 / ( ` )   ' .-./ ). /  '  |   .----'/ `-' \,-./  )
#		. (_ o _)  | \ '_ .') .'   |  _|____  `-'`"`\  '_ '`)
#		|  (_,_)___|(_ (_) _) '    |_( )_   | .---.  > (_)  )
#		'  \   .---.  /    \   \   (_ o._)__| |   | (  .  .-'
#		 \  `-'    /  `-'`-'    \  |(_,_)     |   |  `-'`-'|___
#		  \       /  /  /   \    \ |   |      |   |   |        \
#		   `'-..-'  '--'     '----''---'      '---'   `--------`
#
#		exfil
#
#       is a program that extracts production WordPress databases and updates
#       their local versions in my computer
#
#		version 1.1.1
#



# Requires bash 5
echo "Requires bash 5. Bash version = $BASH_VERSION"

# ask the user to type in a site name
echo "exfil replaces the local copy of a WordPress database with fresh production data."

# perhaps a site name was passed as the first argument
if [ -z "$1" ]
then
	echo "Which site would you like to sync?"
	# TODO the available sites are...
	read site_name
else
	site_name=$1
fi


echo "Loading ${site_name}.conf..."
source "${site_name}.conf"


# CREATE & DOWNLOAD BACKUP

# create the database backup on the server
FILE="${SITE[local_mysql_database]}.sql"
if [ -z "${SITE[ssh_remote_key_file]}" ] # Test if the lengh of STRING is zero (ie it is empty).
then
	echo "Exporting database..."

	# -o delivers option StrictHostKeyChecking=no to avoid a yes/no question and blindly trust the host's ssh key
	# -q suppresses the server welcome message
	# -p specifies the port number
	sshpass -e ssh -q -o StrictHostKeyChecking=no "${SITE[ssh_user_at_host]}" -p "${SITE[ssh_port]}" << EOF
		mysqldump --user="${SITE[production_mysql_user]}" --password="${SITE[production_mysql_password]}" "${SITE[production_mysql_database]}" > "${FILE}"
EOF

	# download the .sql payload
	echo "Downloading .sql file..."
	sshpass -p "${SITE[ssh_password]}" scp -P "${SITE[ssh_port]}" "${SITE[ssh_user_at_host]}":"${SITE[production_root_path]}${FILE}" "${SITE[local_path]}"

	# delete the .sql payload from the server
	echo "Deleting .sql file from server..."
	sshpass -e ssh -o StrictHostKeyChecking=no "${SITE[ssh_user_at_host]}" -p "${SITE[ssh_port]}" "rm -f ${SITE[production_root_path]}${FILE}"

	# maybe download the wp-content folder
	echo "Download the wp-content folder? (y/n)"
	read download_wp_content
	if [ "y" == "$download_wp_content" ]
	then
		echo "Downloading the wp-content folder..."
		sshpass -p "${SITE[ssh_password]}" scp -r -P "${SITE[ssh_port]}" "${SITE[ssh_user_at_host]}":"${SITE[production_path]}wp-content" "${SITE[local_path]}"
	fi


else
	# can't automate this unless we track the password on the key
	# ssh-add /Users/{user-name}/{...}/"${SITE[ssh_remote_key_file]}"

	echo "Exporting database..."

	ssh -q -o StrictHostKeyChecking=no "${SITE[ssh_user_at_host]}" -p "${SITE[ssh_port]}" << EEOF
		mysqldump --user="${SITE[production_mysql_user]}" --password="${SITE[production_mysql_password]}" "${SITE[production_mysql_database]}" > "${FILE}"
EEOF

	# download the .sql payload
	echo "Downloading .sql file..."
	scp -P "${SITE[ssh_port]}" "${SITE[ssh_user_at_host]}":"${SITE[production_root_path]}${FILE}" "${SITE[local_path]}"

	# delete the .sql payload from the server
	echo "Deleting .sql file from server..."
	ssh -o StrictHostKeyChecking=no "${SITE[ssh_user_at_host]}" -p "${SITE[ssh_port]}" "rm -f ${SITE[production_root_path]}${FILE}"

	# maybe download the wp-content folder
	echo "Download the wp-content folder? (y/n)"
	read download_wp_content
	if [ "y" == "$download_wp_content" ]
	then
		echo "Downloading the wp-content folder..."
		scp -r -P "${SITE[ssh_port]}" "${SITE[ssh_user_at_host]}":"${SITE[production_path]}wp-content" "${SITE[local_path]}"
	fi
fi

# if local file does not exist, do not continue
if [ ! -f "${SITE[local_path]}${FILE}" ]; then
	echo "Local .sql file not found, aborting"
	exit
fi



# ALTER FILE AND EXECUTE

# Move to the site folder
cd "${SITE[local_path]}"


# These next commands are commented because I've started using wp-cli to replace URLs and file paths below
# The customizer settings sometimes contain URLs, and those are stored as serialized PHP, so a simple replace breaks the string length counts.
# Replace domain in backup file
#echo "Replacing ${SITE[production_domain]} with ${SITE[local_domain]} in $FILE..."
#LC_ALL=C sed -i '.backup.txt' "s|${SITE[production_domain]}|${SITE[local_domain]}|g" "$FILE"

# Replace again for domains without :// prefixes
#echo "Replacing ${SITE[production_domain]/:\/\//} with ${SITE[local_domain]/:\/\//} in $FILE..."
#LC_ALL=C sed -i '' "s|${SITE[production_domain]/:\/\//}|${SITE[local_domain]/:\/\//}|g" "$FILE"

# Replace file path in backup file
#echo "Replacing ${SITE[production_path]} with ${SITE[local_path]} in $FILE..."
#LC_ALL=C sed -i '' "s|${SITE[production_path]}|${SITE[local_path]}|g" "$FILE"

# Replace again for slashes encoded as %2F
#echo "Replacing ${SITE[production_path]/\//%2F} with ${SITE[local_path]/\//%2F} in $FILE..."
#LC_ALL=C sed -i '' "s|${SITE[production_path]/\//%2F}|${SITE[local_path]/\//%2F}|g" "$FILE"

# Start the MySQL monitor
# Drop all tables in the local database
# Run the file we've downloaded and modified
# If the database has no tables, this will output a few errors. No big deal.
mysql --host=localhost --user="${SITE[local_mysql_user]}" --password="${SITE[local_mysql_password]}" -f --database="${SITE[local_mysql_database]}" <<EOFMYSQL
SET SESSION group_concat_max_len = 1000000;
SET @tables = NULL;
SELECT GROUP_CONCAT('\`', table_schema, '\`.', table_name) INTO @tables FROM information_schema.tables WHERE table_schema = '"${SITE[local_mysql_database]}"';
SET @tables = IF( @tables IS NOT NULL, CONCAT( 'DROP TABLE ', @tables ), '' );
PREPARE stmt1 FROM @tables;
EXECUTE stmt1;
DEALLOCATE PREPARE stmt1;
SET autocommit=0;
source ${SITE[local_path]}$FILE;
COMMIT;
EOFMYSQL

# wp-cli, the WordPress Command Line Interface

# Change admin email to me
# Do not load plugins or themes to avoid debug message output
wp option update admin_email 'corey.salzano@gmail.com' --skip-plugins --skip-themes
wp option update new_admin_email 'corey.salzano@gmail.com' --skip-plugins --skip-themes

# Replace site URLs from production to development
wp search-replace "${SITE[production_domain]}" "${SITE[local_domain]}"
# and file paths
wp search-replace "${SITE[production_path]}" "${SITE[local_path]}"





# Move to the site folder before deletes
cd "${SITE[local_path]}"

# Delete the local .sql files
echo "Delete local .sql files? (y/n)"
read delete_sql_files
if [ "y" == "$delete_sql_files" ]
then
	rm -f "${SITE[local_path]}${FILE}"
	rm -f "${SITE[local_path]}${FILE}.backup.txt"
fi

#TODO disable all gravity forms notifications & feeds