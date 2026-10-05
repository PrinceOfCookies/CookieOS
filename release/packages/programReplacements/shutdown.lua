write("Shut down this Command Authority? [y/N] ");local answer=read():lower();if answer=="y"or answer=="yes"then os.shutdown()else print("Cancelled")end
