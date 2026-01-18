import requests
import xmltodict
import sys


def steamid64_to_steamid(steamid64):
    steamid64 = int(steamid64)
    account_id = (steamid64 - 76561197960265728) & 0xFFFFFFFF
    y = account_id & 1
    z = (account_id - y) >> 1
    return f"STEAM_1:{y}:{z}"


def fetch_and_save_member_ids(group_url_name):
    url = f"https://steamcommunity.com/{group_url_name}/memberslistxml/?xml=1"

    response = requests.get(url)
    if response.status_code != 200:
        raise Exception(f"Error fetching data: {response.status_code}")

    data_dict = xmltodict.parse(response.content)

    member_ids = data_dict["memberList"]["members"]["steamID64"]
    
    group_steamids = set()
    for steamid64 in member_ids:
        steamid = steamid64_to_steamid(steamid64)
        group_steamids.add(steamid)
    
    file_lines = []
    group_section_start = -1
    group_section_end = -1
    
    try:
        with open(f"{txt_name}.txt", "r") as file:
            file_lines = file.readlines()
            
        for i, line in enumerate(file_lines):
            if "// AUTO-MANAGED GROUP MEMBERS - START" in line:
                group_section_start = i
            elif "// AUTO-MANAGED GROUP MEMBERS - END" in line:
                group_section_end = i
                break
    except FileNotFoundError:
        pass

    new_lines = []

    if group_section_start == -1:
        new_lines = file_lines
        if new_lines and not new_lines[-1].endswith('\n'):
            new_lines.append('\n')
        new_lines.append('\n// AUTO-MANAGED GROUP MEMBERS - START\n')
        for steamid in sorted(group_steamids):
            new_lines.append(f"{steamid}\n")
        new_lines.append('// AUTO-MANAGED GROUP MEMBERS - END\n')
        added = len(group_steamids)
        removed = 0
    else:
        new_lines = file_lines[:group_section_start]
        
        old_group_ids = set()
        for i in range(group_section_start + 1, group_section_end):
            line = file_lines[i].strip()
            if line and not line.startswith('//'):
                steamid = line.split('//')[0].strip()
                if steamid.startswith('STEAM_'):
                    old_group_ids.add(steamid)
        
        added = len(group_steamids - old_group_ids)
        removed = len(old_group_ids - group_steamids)

        new_lines.append('// AUTO-MANAGED GROUP MEMBERS - START\n')
        for steamid in sorted(group_steamids):
            new_lines.append(f"{steamid}\n")
        new_lines.append('// AUTO-MANAGED GROUP MEMBERS - END\n')
        
        if group_section_end + 1 < len(file_lines):
            new_lines.extend(file_lines[group_section_end + 1:])
    
    with open(f"{txt_name}.txt", "w") as file:
        file.writelines(new_lines)
    
    print(f"Added {added} new SteamIDs, removed {removed} old SteamIDs")
    print(f"Total group members: {len(group_steamids)}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 list_members.py <txt_file_name> <groups/group_url or gid/group_id>")
        sys.exit(1)
    txt_name = sys.argv[1]
    group_url_name = sys.argv[2]
    fetch_and_save_member_ids(group_url_name)
    print(f"Member IDs have been saved to {txt_name}.txt")
