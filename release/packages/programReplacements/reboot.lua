write("Reboot this Command Authority? [y/N] ");local answer=read():lower();if answer=="y"or answer=="yes"then os.reboot()else print("Cancelled")end
